class PlaidAccount::Liabilities::MortgageProcessor
  def initialize(external_account)
    @external_account = external_account
  end

  def process
    return unless mortgage_data.present?

    account.loan.update!(
      rate_type: mortgage_data.dig("interest_rate", "type"),
      interest_rate: mortgage_data.dig("interest_rate", "percentage")
    )
  end

  private
    attr_reader :external_account

    def account
      external_account.account
    end

    def mortgage_data
      external_account.raw_liabilities_payload["mortgage"]
    end
end
