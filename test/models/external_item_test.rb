require "test_helper"

class ExternalItemTest < ActiveSupport::TestCase
  include SyncableInterfaceTest

  setup do
    @external_item = @syncable = external_items(:one)
    @plaid_provider = mock
    Provider::Registry.stubs(:plaid_provider_for_region).returns(@plaid_provider)
  end

  test "removes plaid item when destroyed" do
    @plaid_provider.expects(:remove_item).with(@external_item.access_token).once

    assert_difference "ExternalItem.count", -1 do
      @external_item.destroy
    end
  end
end
