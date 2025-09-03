class Provider::PlaidAdapter
  def item_payload(data)
    data = data.as_json.deep_symbolize_keys
    {
      available_products: data[:available_products],
      billed_products: data[:billed_products]
    }
  end

  def institution_payload(data)
    data = data.as_json.deep_symbolize_keys
    {
      name: data[:name],
      institution_id: data[:institution_id],
      url: data[:url],
      primary_color: data[:primary_color]
    }
  end

  def account_payload(data)
    data = data.as_json.deep_symbolize_keys
    {
      account_id: data[:account_id],
      name: data[:name],
      type: data[:type],
      subtype: data[:subtype],
      mask: data[:mask],
      current_balance: data[:balances][:current],
      available_balance: data[:balances][:available],
      currency: data[:balances][:iso_currency_code]
    }
  end

  def transactions_payload(data)
    data = data.as_json.deep_symbolize_keys
    {
      modified: data[:modified]&.map do |t|
        {
          transaction_id: t[:transaction_id],
          merchant_id: t[:merchant_entity_id],
          merchant_name: t[:merchant_name],
          description: t[:original_description],
          amount: t[:amount],
          date: t[:date],
          iso_currency_code: t[:iso_currency_code],
          category: t.dig(:personal_finance_category, :detailed),
          website: t[:website],
          logo_url: t[:logo_url]
        }
      end,
      added: data[:added]&.map do |t|
        {
          transaction_id: t[:transaction_id],
          merchant_id: t[:merchant_entity_id],
          merchant_name: t[:merchant_name],
          description: t[:original_description],
          amount: t[:amount],
          date: t[:date],
          iso_currency_code: t[:iso_currency_code],
          category: t.dig(:personal_finance_category, :detailed)
        }
      end,
      removed: data[:removed]&.map do |t| { transaction_id: t[:transaction_id] } end
      }
  end

  def investments_payload(data)
    data = data.as_json.deep_symbolize_keys
    {
      holdings: data[:holdings]&.map do |h|
        {
          security_id: h[:security_id],
          institution_price: h[:institution_price],
          quantity: h[:quantity],
          iso_currency_code: h[:iso_currency_code],
          institution_price_as_of: h[:institution_price_as_of]
        }
      end,
      securities: data[:securities]&.map do |s|
      {
        type: s[:type],
        security_id: s[:security_id],
        ticker_symbol: s[:ticker_symbol],
        proxy_security_id: s[:proxy_security_id],
        iso_currency_code: s[:iso_currency_code],
        market_identifier_code: s[:market_identifier_code],
        is_cash_equivalent: s[:is_cash_equivalent]
      }
    end
    }
  end

  def liabilities_payload(data)
    data
  end
end
