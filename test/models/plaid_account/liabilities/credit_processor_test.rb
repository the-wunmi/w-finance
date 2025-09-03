require "test_helper"

class ExternalAccount::Liabilities::CreditProcessorTest < ActiveSupport::TestCase
  setup do
    @external_account = external_accounts(:one)
    @external_account.update!(
      plaid_type: "credit",
      plaid_subtype: "credit_card"
    )

    @external_account.account.update!(
      accountable: CreditCard.new,
    )
  end

  test "updates credit card minimum payment and APR from Plaid data" do
    @external_account.update!(raw_liabilities_payload: {
      credit: {
        minimum_payment_amount: 100,
        aprs: [ { apr_percentage: 15.0 } ]
      }
    })

    processor = ExternalAccount::Liabilities::CreditProcessor.new(@external_account)
    processor.process

    assert_equal 100, @external_account.account.credit_card.minimum_payment
    assert_equal 15.0, @external_account.account.credit_card.apr
  end

  test "does nothing when liability data absent" do
    @external_account.update!(raw_liabilities_payload: {})
    processor = ExternalAccount::Liabilities::CreditProcessor.new(@external_account)
    processor.process

    assert_nil @external_account.account.credit_card.minimum_payment
    assert_nil @external_account.account.credit_card.apr
  end
end
