module Family::PlaidConnectable
  extend ActiveSupport::Concern

  included do
    has_many :external_items, dependent: :destroy
  end

  def create_external_item!(public_token:, item_name:, provider_name: "plaid_us")
    provider = Provider::Registry.get_provider(provider_name.to_sym)
    public_token_response = provider.exchange_public_token(public_token)

    external_item = external_items.create!(
      name: item_name || "Unknown",
      external_id: public_token_response.item_id,
      access_token: public_token_response.access_token,
      provider: provider_name
    )

    external_item.sync_later

    external_item
  end

  def get_link_token(webhooks_url:, redirect_url:, accountable_type: nil, provider_name: "plaid_us", access_token: nil)
    provider = Provider::Registry.get_provider(provider_name.to_sym)

    return nil unless provider.present?

    provider.get_link_token(
      user_id: self.id,
      webhooks_url: webhooks_url,
      redirect_url: redirect_url,
      accountable_type: accountable_type,
      access_token: access_token
    )
  end
end
