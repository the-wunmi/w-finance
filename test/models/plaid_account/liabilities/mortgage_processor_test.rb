require "test_helper"

class ExternalAccount::Liabilities::MortgageProcessorTest < ActiveSupport::TestCase
  setup do
    @external_account = external_accounts(:one)
    @external_account.update!(
      plaid_type: "loan",
      plaid_subtype: "mortgage"
    )

    @external_account.account.update!(accountable: Loan.new)
  end

  test "updates loan interest rate and type from Plaid data" do
    @external_account.update!(raw_liabilities_payload: {
      mortgage: {
        interest_rate: {
          type: "fixed",
          percentage: 4.25
        }
      }
    })

    processor = ExternalAccount::Liabilities::MortgageProcessor.new(@external_account)
    processor.process

    loan = @external_account.account.loan

    assert_equal "fixed", loan.rate_type
    assert_equal 4.25, loan.interest_rate
  end

  test "does nothing when mortgage data absent" do
    @external_account.update!(raw_liabilities_payload: {})

    processor = ExternalAccount::Liabilities::MortgageProcessor.new(@external_account)
    processor.process

    loan = @external_account.account.loan

    assert_nil loan.rate_type
    assert_nil loan.interest_rate
  end
end
