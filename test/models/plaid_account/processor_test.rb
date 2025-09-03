require "test_helper"

class ExternalAccount::ProcessorTest < ActiveSupport::TestCase
  setup do
    @external_account = external_accounts(:one)
  end

  test "processes new account and assigns attributes" do
    Account.destroy_all # Clear out internal accounts so we start fresh

    expect_default_subprocessor_calls

    @external_account.update!(
      plaid_id: "test_plaid_id",
      plaid_type: "depository",
      plaid_subtype: "checking",
      current_balance: 1000,
      available_balance: 1000,
      currency: "USD",
      name: "Test Plaid Account",
      mask: "1234"
    )

    assert_difference "Account.count" do
      ExternalAccount::Processor.new(@external_account).process
    end

    @external_account.reload

    account = Account.order(created_at: :desc).first
    assert_equal "Test Plaid Account", account.name
    assert_equal @external_account.id, account.external_account_id
    assert_equal "checking", account.subtype
    assert_equal 1000, account.balance
    assert_equal 1000, account.cash_balance
    assert_equal "USD", account.currency
    assert_equal "Depository", account.accountable_type
    assert_equal "checking", account.subtype
  end

  test "processing is idempotent with updates and enrichments" do
    expect_default_subprocessor_calls

    assert_equal "Plaid Depository Account", @external_account.account.name
    assert_equal "checking", @external_account.account.subtype

    @external_account.account.update!(
      name: "User updated name",
      subtype: "savings",
      balance: 2000 # User cannot override balance.  This will be overridden by the processor on next processing
    )

    @external_account.account.lock_attr!(:name)
    @external_account.account.lock_attr!(:subtype)
    @external_account.account.lock_attr!(:balance) # Even if balance somehow becomes locked, Plaid ignores it and overrides it

    assert_no_difference "Account.count" do
      ExternalAccount::Processor.new(@external_account).process
    end

    @external_account.reload

    assert_equal "User updated name", @external_account.account.name
    assert_equal "savings", @external_account.account.subtype
    assert_equal @external_account.current_balance, @external_account.account.balance # Overriden by processor
  end

  test "account processing failure halts further processing" do
    Account.any_instance.stubs(:save!).raises(StandardError.new("Test error"))

    ExternalAccount::Transactions::Processor.any_instance.expects(:process).never
    ExternalAccount::Investments::TransactionsProcessor.any_instance.expects(:process).never
    ExternalAccount::Investments::HoldingsProcessor.any_instance.expects(:process).never

    expect_no_investment_balance_calculator_calls
    expect_no_liability_processor_calls

    assert_raises(StandardError) do
      ExternalAccount::Processor.new(@external_account).process
    end
  end

  test "product processing failure reports exception and continues processing" do
    ExternalAccount::Transactions::Processor.any_instance.stubs(:process).raises(StandardError.new("Test error"))

    # Subsequent product processors still run
    expect_investment_product_processor_calls

    assert_nothing_raised do
      ExternalAccount::Processor.new(@external_account).process
    end
  end

  test "calculates balance using BalanceCalculator for investment accounts" do
    @external_account.update!(plaid_type: "investment")

    # Balance is called twice: once for account.balance and once for set_current_balance
    ExternalAccount::Investments::BalanceCalculator.any_instance.expects(:balance).returns(1000).twice
    ExternalAccount::Investments::BalanceCalculator.any_instance.expects(:cash_balance).returns(1000).once

    ExternalAccount::Processor.new(@external_account).process

    # Verify that the balance was set correctly
    account = @external_account.account
    assert_equal 1000, account.balance
    assert_equal 1000, account.cash_balance

    # Verify current balance anchor was created with correct value
    current_anchor = account.valuations.current_anchor.first
    assert_not_nil current_anchor
    assert_equal 1000, current_anchor.entry.amount
  end

  test "processes credit liability data" do
    expect_investment_product_processor_calls
    expect_no_investment_balance_calculator_calls
    expect_depository_product_processor_calls

    @external_account.update!(plaid_type: "credit", plaid_subtype: "credit card")

    ExternalAccount::Liabilities::CreditProcessor.any_instance.expects(:process).once
    ExternalAccount::Liabilities::MortgageProcessor.any_instance.expects(:process).never
    ExternalAccount::Liabilities::StudentLoanProcessor.any_instance.expects(:process).never

    ExternalAccount::Processor.new(@external_account).process
  end

  test "processes mortgage liability data" do
    expect_investment_product_processor_calls
    expect_no_investment_balance_calculator_calls
    expect_depository_product_processor_calls

    @external_account.update!(plaid_type: "loan", plaid_subtype: "mortgage")

    ExternalAccount::Liabilities::CreditProcessor.any_instance.expects(:process).never
    ExternalAccount::Liabilities::MortgageProcessor.any_instance.expects(:process).once
    ExternalAccount::Liabilities::StudentLoanProcessor.any_instance.expects(:process).never

    ExternalAccount::Processor.new(@external_account).process
  end

  test "processes student loan liability data" do
    expect_investment_product_processor_calls
    expect_no_investment_balance_calculator_calls
    expect_depository_product_processor_calls

    @external_account.update!(plaid_type: "loan", plaid_subtype: "student")

    ExternalAccount::Liabilities::CreditProcessor.any_instance.expects(:process).never
    ExternalAccount::Liabilities::MortgageProcessor.any_instance.expects(:process).never
    ExternalAccount::Liabilities::StudentLoanProcessor.any_instance.expects(:process).once

    ExternalAccount::Processor.new(@external_account).process
  end

  test "creates current balance anchor when processing account" do
    expect_default_subprocessor_calls

    # Clear out accounts to start fresh
    Account.destroy_all

    @external_account.update!(
      plaid_id: "test_plaid_id",
      plaid_type: "depository",
      plaid_subtype: "checking",
      current_balance: 1500,
      available_balance: 1500,
      currency: "USD",
      name: "Test Account with Anchor",
      mask: "1234"
    )

    assert_difference "Account.count", 1 do
      assert_difference "Entry.count", 1 do
        assert_difference "Valuation.count", 1 do
          ExternalAccount::Processor.new(@external_account).process
        end
      end
    end

    account = Account.order(created_at: :desc).first
    assert_equal 1500, account.balance

    # Verify current balance anchor was created
    current_anchor = account.valuations.current_anchor.first
    assert_not_nil current_anchor
    assert_equal "current_anchor", current_anchor.kind
    assert_equal 1500, current_anchor.entry.amount
    assert_equal Date.current, current_anchor.entry.date
    assert_equal "Current balance", current_anchor.entry.name
  end

  test "updates existing current balance anchor when reprocessing" do
    # First process creates the account and anchor
    expect_default_subprocessor_calls
    ExternalAccount::Processor.new(@external_account).process

    account = @external_account.account
    original_anchor = account.valuations.current_anchor.first
    assert_not_nil original_anchor
    original_anchor_id = original_anchor.id
    original_entry_id = original_anchor.entry.id
    original_balance = original_anchor.entry.amount

    # Update the plaid account balance
    @external_account.update!(current_balance: 2500)

    # Expect subprocessor calls again for the second processing
    expect_default_subprocessor_calls

    # Reprocess should update the existing anchor
    assert_no_difference "Valuation.count" do
      assert_no_difference "Entry.count" do
        ExternalAccount::Processor.new(@external_account).process
      end
    end

    # Verify the anchor was updated
    original_anchor.reload
    assert_equal original_anchor_id, original_anchor.id
    assert_equal original_entry_id, original_anchor.entry.id
    assert_equal 2500, original_anchor.entry.amount
    assert_not_equal original_balance, original_anchor.entry.amount
  end

  private
    def expect_investment_product_processor_calls
      ExternalAccount::Investments::TransactionsProcessor.any_instance.expects(:process).once
      ExternalAccount::Investments::HoldingsProcessor.any_instance.expects(:process).once
    end

    def expect_depository_product_processor_calls
      ExternalAccount::Transactions::Processor.any_instance.expects(:process).once
    end

    def expect_no_investment_balance_calculator_calls
      ExternalAccount::Investments::BalanceCalculator.any_instance.expects(:balance).never
      ExternalAccount::Investments::BalanceCalculator.any_instance.expects(:cash_balance).never
    end

    def expect_no_liability_processor_calls
      ExternalAccount::Liabilities::CreditProcessor.any_instance.expects(:process).never
      ExternalAccount::Liabilities::MortgageProcessor.any_instance.expects(:process).never
      ExternalAccount::Liabilities::StudentLoanProcessor.any_instance.expects(:process).never
    end

    def expect_default_subprocessor_calls
      expect_depository_product_processor_calls
      expect_investment_product_processor_calls
      expect_no_investment_balance_calculator_calls
      expect_no_liability_processor_calls
    end
end
