class ExternalAccount::Liabilities::CreditProcessor
  def initialize(external_account)
    @external_account = external_account
  end

  def process
    return unless credit_data.present?

    account.credit_card.update!(
      minimum_payment: credit_data.dig("minimum_payment_amount"),
      apr: credit_data.dig("aprs", 0, "apr_percentage")
    )
  end

  private
    attr_reader :external_account

    def account
      external_account.account
    end

    def credit_data
      external_account.raw_liabilities_payload["credit"]
    end
end
