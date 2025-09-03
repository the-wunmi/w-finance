class ExternalItemsController < ApplicationController
  before_action :set_external_item, only: %i[edit destroy sync]

  def new
    case params[:provider]
    when "plaid_eu"
      webhooks_url = plaid_eu_webhooks_url
    when "plaid_us"
      webhooks_url = plaid_us_webhooks_url
    when "mono"
      webhooks_url = mono_webhooks_url
    else
      webhooks_url = nil
    end

    @link_token = Current.family.get_link_token(
      webhooks_url: webhooks_url,
      redirect_url: accounts_url,
      accountable_type: params[:accountable_type] || "Depository",
      provider_name:  params[:provider]
    )
  end

  def edit
    webhooks_url = @external_item.provider == "plaid_eu" ? plaid_eu_webhooks_url : plaid_us_webhooks_url

    @link_token = @external_item.get_update_link_token(
      webhooks_url: webhooks_url,
      redirect_url: accounts_url,
    )
  end

  def create
    Current.family.create_external_item!(
      public_token: external_item_params[:public_token],
      item_name: item_name,
      provider_name: external_item_params[:provider]
    )

    redirect_to accounts_path, notice: t(".success")
  end

  def destroy
    @external_item.destroy_later
    redirect_to accounts_path, notice: t(".success")
  end

  def sync
    unless @external_item.syncing?
      @external_item.sync_later
    end

    respond_to do |format|
      format.html { redirect_back_or_to accounts_path }
      format.json { head :ok }
    end
  end

  private
    def set_external_item
      @external_item = Current.family.external_items.find(params[:id])
    end

    def external_item_params
      params.require(:external_item).permit(:public_token, :provider, metadata: {})
    end

    def item_name
      external_item_params.dig(:metadata, :institution, :name)
    end

    def plaid_us_webhooks_url
      return webhooks_plaid_url if Rails.env.production?

      ENV.fetch("DEV_WEBHOOKS_URL", root_url.chomp("/")) + "/webhooks/plaid"
    end

    def plaid_eu_webhooks_url
      return webhooks_plaid_eu_url if Rails.env.production?

      ENV.fetch("DEV_WEBHOOKS_URL", root_url.chomp("/")) + "/webhooks/plaid_eu"
    end

    def mono_webhooks_url
      return webhooks_mono_url if Rails.env.production?

      ENV.fetch("DEV_WEBHOOKS_URL", root_url.chomp("/")) + "/webhooks/mono"
    end
end
