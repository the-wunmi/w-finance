class ExternalItem::Importer
  def initialize(external_item, plaid_provider:)
    @external_item = external_item
    @plaid_provider = plaid_provider
  end

  def import
    fetch_and_import_item_data
    fetch_and_import_accounts_data
  rescue Plaid::ApiError => e
    handle_plaid_error(e)
  end

  private
    attr_reader :external_item, :plaid_provider

    # All errors that should halt the import should be re-raised after handling
    # These errors will propagate up to the Sync record and mark it as failed.
    def handle_plaid_error(error)
      error_body = JSON.parse(error.response_body)

      case error_body["error_code"]
      when "ITEM_LOGIN_REQUIRED"
        external_item.update!(status: :requires_update)
      else
        raise error
      end
    end

    def fetch_and_import_item_data
      item_data = plaid_provider.get_item(external_item.access_token).item
      institution_data = plaid_provider.get_institution(item_data.institution_id).institution

      external_item.upsert_external_snapshot!(item_data)
      external_item.upsert_institution_snapshot!(institution_data)
    end

    def fetch_and_import_accounts_data
      snapshot = ExternalItem::AccountsSnapshot.new(external_item, plaid_provider: plaid_provider)

      ExternalItem.transaction do
        snapshot.accounts.each do |raw_account|
          external_account = external_item.external_accounts.find_or_initialize_by(
            external_id: raw_account.account_id
          )

          ExternalAccount::Importer.new(
            external_account,
            account_snapshot: snapshot.get_account_data(raw_account.account_id)
          ).import
        end

        # Once we know all data has been imported, save the cursor to avoid re-fetching the same data next time
        external_item.update!(next_cursor: snapshot.transactions_cursor)
      end
    end
end
