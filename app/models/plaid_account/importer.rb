class PlaidAccount::Importer
  def initialize(external_account, account_snapshot:)
    @external_account = external_account
    @account_snapshot = account_snapshot
  end

  def import
    import_account_info
    import_transactions if account_snapshot.transactions_data.present?
    import_investments if account_snapshot.investments_data.present?
    import_liabilities if account_snapshot.liabilities_data.present?
  end

  private
    attr_reader :external_account, :account_snapshot

    def import_account_info
      external_account.upsert_external_snapshot!(account_snapshot.account_data)
    end

    def import_transactions
      external_account.upsert_transactions_snapshot!(account_snapshot.transactions_data)
    end

    def import_investments
      external_account.upsert_investments_snapshot!(account_snapshot.investments_data)
    end

    def import_liabilities
      external_account.upsert_liabilities_snapshot!(account_snapshot.liabilities_data)
    end
end
