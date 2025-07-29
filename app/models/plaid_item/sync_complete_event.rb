class PlaidItem::SyncCompleteEvent
  attr_reader :external_item

  def initialize(external_item)
    @external_item = external_item
  end

  def broadcast
    external_item.accounts.each do |account|
      account.broadcast_sync_complete
    end

    external_item.broadcast_replace_to(
      external_item.family,
      target: "external_item_#{external_item.id}",
      partial: "external_items/external_item",
      locals: { external_item: external_item }
    )

    external_item.family.broadcast_sync_complete
  end
end
