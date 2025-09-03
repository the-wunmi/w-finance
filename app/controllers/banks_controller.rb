class BanksController < ApplicationController
  def index
    @banks = BankProvider.active.for_country(Current.family.country).by_name
  end

  def show
    @bank = BankProvider.find(params[:id])
  end
end
