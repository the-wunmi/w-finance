class Provider::DataProviderAdapter
  def initialize(provider)
    @provider = provider
  end

  def item_payload(data)
    adapter.item_payload(data)
  end

  def institution_payload(data)
    adapter.institution_payload(data)
  end

  def account_payload(data)
    adapter.account_payload(data)
  end

  def transactions_payload(data)
    adapter.transactions_payload(data)
  end

  def investments_payload(data)
    adapter.investments_payload(data)
  end

  def liabilities_payload(data)
    adapter.liabilities_payload(data)
  end

  private
    def adapter
      case @provider
      when "plaid_us", "plaid_eu"
        Provider::PlaidAdapter.new
      when "mono"
        Provider::MonoAdapter.new
      when "doubleu"
        Provider::DoubleuAdapter.new
      else
        raise "Unsupported provider: #{@provider}"
      end
    end
end
