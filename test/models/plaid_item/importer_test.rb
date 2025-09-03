require "test_helper"
require "ostruct"

class ExternalItem::ImporterTest < ActiveSupport::TestCase
  setup do
    @mock_provider = mock("Provider::Plaid")
    @external_item = external_items(:one)
    @importer = ExternalItem::Importer.new(@external_item, plaid_provider: @mock_provider)
  end

  test "imports item metadata" do
    item_data = OpenStruct.new(
      item_id: "item_1",
      available_products: [ "transactions", "investments", "liabilities" ],
      billed_products: [],
      institution_id: "ins_1",
      institution_name: "First Platypus Bank",
    )

    @mock_provider.expects(:get_item).with(@external_item.access_token).returns(
      OpenStruct.new(item: item_data)
    )

    institution_data = OpenStruct.new(
      institution_id: "ins_1",
      institution_name: "First Platypus Bank",
    )

    @mock_provider.expects(:get_institution).with("ins_1").returns(
      OpenStruct.new(institution: institution_data)
    )

    ExternalItem::AccountsSnapshot.any_instance.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "acc_1",
        type: "depository",
      )
    ]).at_least_once

    ExternalItem::AccountsSnapshot.any_instance.expects(:transactions_cursor).returns("test_cursor_1")

    ExternalItem::AccountsSnapshot.any_instance.expects(:get_account_data).with("acc_1").once

    ExternalAccount::Importer.any_instance.expects(:import).once

    @external_item.expects(:update!).with(next_cursor: "test_cursor_1")
    @external_item.expects(:upsert_plaid_snapshot!).with(item_data)
    @external_item.expects(:upsert_plaid_institution_snapshot!).with(institution_data)

    @importer.import
  end
end
