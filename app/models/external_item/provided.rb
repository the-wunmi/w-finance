module ExternalItem::Provided
  extend ActiveSupport::Concern

  def plaid_provider
    @plaid_provider ||= Provider::Registry.get_provider(self.provider)
  end
end
