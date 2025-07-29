class PlaidItemsController < ApplicationController
  before_action :set_external_item, only: %i[edit destroy sync]

  def new
    region = params[:region] == "eu" ? :eu : :us
    webhooks_url = region == :eu ? plaid_eu_webhooks_url : plaid_us_webhooks_url

    @link_token = Current.family.get_link_token(
      webhooks_url: webhooks_url,
      redirect_url: accounts_url,
      accountable_type: params[:accountable_type] || "Depository",
      region: region
    )
  end

  def edit
    webhooks_url = @external_item.plaid_region == "eu" ? plaid_eu_webhooks_url : plaid_us_webhooks_url

    @link_token = @external_item.get_update_link_token(
      webhooks_url: webhooks_url,
      redirect_url: accounts_url,
    )
  end

  def create
    Current.family.create_external_item!(
      public_token: external_item_params[:public_token],
      item_name: item_name,
      region: external_item_params[:region]
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
      params.require(:external_item).permit(:public_token, :region, metadata: {})
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
end
