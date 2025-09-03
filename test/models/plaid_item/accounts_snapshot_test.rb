require "test_helper"

class ExternalItem::AccountsSnapshotTest < ActiveSupport::TestCase
  setup do
    @external_item = external_items(:one)
    @external_item.external_accounts.destroy_all # Clean slate

    @plaid_provider = mock
    @snapshot = ExternalItem::AccountsSnapshot.new(@external_item, plaid_provider: @plaid_provider)
  end

  test "fetches accounts" do
    @plaid_provider.expects(:get_item_accounts).with(@external_item.access_token).returns(
      OpenStruct.new(accounts: [])
    )
    @snapshot.accounts
  end

  test "fetches transactions data if item supports transactions and any accounts present" do
    @external_item.update!(available_products: [ "transactions" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "depository"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).with(@external_item.access_token, next_cursor: nil).returns(
      OpenStruct.new(
        added: [],
        modified: [],
        removed: [],
        cursor: "test_cursor_1"
      )
    ).once
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "does not fetch transactions if no accounts" do
    @external_item.update!(available_products: [ "transactions" ], billed_products: [])

    @snapshot.expects(:accounts).returns([]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "updates next_cursor when fetching transactions" do
    @external_item.update!(available_products: [ "transactions" ], billed_products: [], next_cursor: "test_cursor_1")

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "depository"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).with(@external_item.access_token, next_cursor: "test_cursor_1").returns(
      OpenStruct.new(
        added: [],
        modified: [],
        removed: [],
        cursor: "test_cursor_2"
      )
    ).once

    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "fetches investments data if item supports investments and investment accounts present" do
    @external_item.update!(available_products: [ "investments" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "investment"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).with(@external_item.access_token).once
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "does not fetch investments if no investment accounts" do
    @external_item.update!(available_products: [ "investments" ], billed_products: [])

    @snapshot.expects(:accounts).returns([]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "fetches liabilities data if item supports liabilities and liabilities accounts present" do
    @external_item.update!(available_products: [ "liabilities" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "loan",
        subtype: "student"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).with(@external_item.access_token).once

    @snapshot.get_account_data("123")
  end

  test "does not fetch liabilities if no liabilities accounts" do
    @external_item.update!(available_products: [ "liabilities" ], billed_products: [])

    @snapshot.expects(:accounts).returns([]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end
end
