class Provider::Plaid
  attr_reader :client, :region

  DOUBLEU_SUPPORTED_PLAID_PRODUCTS = %w[transactions investments liabilities].freeze
  MAX_HISTORY_DAYS = Rails.env.development? ? 90 : 730

  def initialize(config, region: :us)
    @client = Plaid::PlaidApi.new(
      Plaid::ApiClient.new(config)
    )
    @region = region
  end

  def validate_webhook!(verification_header, raw_body)
    jwks_loader = ->(options) do
      key_id = options[:kid]

      jwk_response = client.webhook_verification_key_get(
        Plaid::WebhookVerificationKeyGetRequest.new(key_id: key_id)
      )

      jwks = JWT::JWK::Set.new([ jwk_response.key.to_hash ])

      jwks.filter! { |key| key[:use] == "sig" }
      jwks
    end

    payload, _header = JWT.decode(
      verification_header, nil, true,
      {
        algorithms: [ "ES256" ],
        jwks: jwks_loader,
        verify_expiration: false
      }
    )

    issued_at = Time.at(payload["iat"])
    raise JWT::VerificationError, "Webhook is too old" if Time.now - issued_at > 5.minutes

    expected_hash = payload["request_body_sha256"]
    actual_hash = Digest::SHA256.hexdigest(raw_body)
    raise JWT::VerificationError, "Invalid webhook body hash" unless ActiveSupport::SecurityUtils.secure_compare(expected_hash, actual_hash)
  end

  def get_link_token(user_id:, webhooks_url:, redirect_url:, accountable_type: nil, access_token: nil)
    request_params = {
      user: { client_user_id: user_id },
      client_name: "DoubleU Finance",
      country_codes: country_codes,
      language: "en",
      webhook: webhooks_url,
      redirect_uri: redirect_url,
      transactions: { days_requested: MAX_HISTORY_DAYS }
    }

    if access_token.present?
      request_params[:access_token] = access_token
    else
      request_params[:products] = [ get_primary_product(accountable_type) ]
      request_params[:additional_consented_products] = get_additional_consented_products(accountable_type)
    end

    request = Plaid::LinkTokenCreateRequest.new(request_params)

    client.link_token_create(request).link_token
  end

  def exchange_public_token(token)
    request = Plaid::ItemPublicTokenExchangeRequest.new(
      public_token: token
    )

    client.item_public_token_exchange(request)
  end

  def get_item(external_item)
    request = Plaid::ItemGetRequest.new(access_token: external_item.access_token)
    client.item_get(request).item
  end

  def remove_item(external_item)
    request = Plaid::ItemRemoveRequest.new(access_token: external_item.access_token)
    client.item_remove(request)
    nil
  end

  def get_item_accounts(external_item)
    request = Plaid::AccountsGetRequest.new(access_token: external_item.access_token)
    client.accounts_get(request).accounts
  end

  def get_transactions(external_item, account_id, next_cursor: nil)
    cursor = next_cursor
    added = []
    modified = []
    removed = []
    has_more = true

    while has_more
      request = Plaid::TransactionsSyncRequest.new(
        access_token: external_item.access_token,
        cursor: cursor,
        options: {
          include_original_description: true,
          account_id: account_id
        }
      )

      response = client.transactions_sync(request)

      added += response.added
      modified += response.modified
      removed += response.removed
      has_more = response.has_more
      cursor = response.next_cursor
    end

    TransactionSyncResponse.new(added:, modified:, removed:, cursor:)
  end

  def get_item_investments(external_item, account_id, start_date: nil, end_date: Date.current)
    begin
      start_date = start_date || MAX_HISTORY_DAYS.days.ago.to_date
      holdings, holding_securities = get_item_holdings(external_item.access_token, account_id)
      transactions, transaction_securities = get_item_investment_transactions(external_item.access_token, account_id, start_date:, end_date:)

      merged_securities = ((holding_securities || []) + (transaction_securities || [])).uniq { |s| s.security_id }

      InvestmentsResponse.new(holdings:, transactions:, securities: merged_securities)
    rescue Plaid::ApiError => e
      json_response = JSON.parse(e.response_body)
      raise e unless json_response["error_code"] == "NO_INVESTMENT_ACCOUNTS"
      nil
    end
  end

  def get_item_liabilities(external_item, account_id)
    begin
      request = Plaid::LiabilitiesGetRequest.new(access_token: external_item.access_token, options: { account_ids: [ account_id ] })
      response = client.liabilities_get(request)
      response.liabilities
    rescue Plaid::ApiError => e
      json_response = JSON.parse(e.response_body)
      raise e unless json_response["error_code"] == "NO_LIABILITY_ACCOUNTS"
      nil
    end
  end

  def get_institution(item_data)
    request = Plaid::InstitutionsGetByIdRequest.new({
      institution_id: item_data.institution_id,
      country_codes: country_codes,
      options: {
        include_optional_metadata: true
      }
    })
    client.institutions_get_by_id(request).institution
  end

  private
    TransactionSyncResponse = Struct.new :added, :modified, :removed, :cursor, keyword_init: true
    InvestmentsResponse = Struct.new :holdings, :transactions, :securities, keyword_init: true

    def get_item_holdings(access_token, account_id)
      request = Plaid::InvestmentsHoldingsGetRequest.new(
        access_token: access_token,
        options: { account_ids: [ account_id ] }
      )
      response = client.investments_holdings_get(request)

      [ response.holdings, response.securities ]
    end

    def get_item_investment_transactions(access_token, account_id, start_date:, end_date:)
      transactions = []
      securities = []
      offset = 0

      loop do
        request = Plaid::InvestmentsTransactionsGetRequest.new(
          access_token: access_token,
          start_date: start_date.to_s,
          end_date: end_date.to_s,
          options: { offset: offset, account_ids: [ account_id ] }
        )

        response = client.investments_transactions_get(request)

        transactions += response.investment_transactions
        securities += response.securities

        break if transactions.length >= response.total_investment_transactions
        offset = transactions.length
      end

      [ transactions, securities ]
    end

    def get_primary_product(accountable_type)
      return "transactions" if eu?

      case accountable_type
      when "Investment"
        "investments"
      when "CreditCard", "Loan"
        "liabilities"
      else
        "transactions"
      end
    end

    def get_additional_consented_products(accountable_type)
      return [] if eu?

      DOUBLEU_SUPPORTED_PLAID_PRODUCTS - [ get_primary_product(accountable_type) ]
    end

    def eu?
      region.to_sym == :eu
    end

    def country_codes
      if eu?
        [ "ES", "NL", "FR", "IE", "DE", "IT", "PL", "DK", "NO", "SE", "EE", "LT", "LV", "PT", "BE" ]  # EU supported countries
      else
        [ "US", "CA" ] # US + CA only
      end
    end
end
