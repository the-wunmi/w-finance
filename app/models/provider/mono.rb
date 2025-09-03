class Provider::Mono
  attr_reader :secret_key, :client

  DOUBLEU_SUPPORTED_MONO_PRODUCTS = %w[transactions accounts].freeze
  BASE_URL = "https://api.withmono.com"

  def initialize(secret_key)
    @secret_key = secret_key
    @client = Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def validate_webhook!(verification_header, raw_body)
    expected_signature = verification_header
    computed_signature = OpenSSL::HMAC.hexdigest("SHA512", secret_key, raw_body)

    unless ActiveSupport::SecurityUtils.secure_compare(expected_signature, computed_signature)
      raise JWT::VerificationError, "Invalid webhook signature"
    end
  end

  def get_link_token(user_id:, webhooks_url:, redirect_url:, accountable_type: nil, access_token: nil)
    ENV["MONO_PUBLIC_KEY"]
  end

  def exchange_public_token(code)
    response = client.post("/account/auth") do |req|
      req.headers["mono-sec-key"] = secret_key
      req.body = { code: code }
    end
    OpenStruct.new(item_id: handle_response(response)["id"])
  end

  def get_item(external_item)
    response = client.get("/v2/accounts/#{external_item.external_id}") do |req|
      req.headers["mono-sec-key"] = secret_key
    end
    handle_response(response)["data"]
  end

  def remove_item(external_item)
    response = client.post("/v2/accounts/#{external_item.external_id}/unlink") do |req|
      req.headers["mono-sec-key"] = secret_key
    end
    handle_response(response)["data"]
  end

  def get_item_accounts(external_item)
    response = client.get("/v2/accounts/#{external_item.external_id}") do |req|
      req.headers["mono-sec-key"] = secret_key
    end
    [ handle_response(response)["data"]["account"] ]
  end

  def get_transactions(external_item, account_id, next_cursor: nil)
    params = { paginate: false }
    params["x-real-time"] = true if next_cursor

    response = client.get("/v2/accounts/#{external_item.external_id}/transactions") do |req|
      req.headers["mono-sec-key"] = secret_key
      req.params = params
    end
    data = handle_response(response)
    transactions = data["data"].sort_by { |txn| DateTime.parse(txn["date"]) }.reverse

    if next_cursor
      transactions = transactions[0...transactions.index { |t| t["id"] == next_cursor }]
    end

    TransactionSyncResponse.new(
      added: transactions,
      modified: [],
      removed: [],
      cursor: transactions.first&.dig("id")
    )
  end

  def get_item_investments(external_item, account_id)
    nil
  end

  def get_item_liabilities(external_item, account_id)
    nil
  end

  def get_institution(item_data)
    item_data["account"]["institution"]
  end

  private
    TransactionSyncResponse = Struct.new(:added, :modified, :removed, :cursor, keyword_init: true)
    InvestmentsResponse = Struct.new(:holdings, :transactions, :securities, keyword_init: true)

    def handle_response(response)
      unless response.success?
        raise MonoApiError.new("Mono API error: #{response.status} - #{response.body}")
      end

      response.body
    end

    class MonoApiError < StandardError; end
end
