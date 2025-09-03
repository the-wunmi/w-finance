class Provider::DoubleuAdapter
  def item_payload(data)
    {
      available_products: data["available_products"],
      billed_products: data["available_products"]
    }
  end

  def institution_payload(data)
    {
      name: data["name"],
      institution_id: data["institution_id"],
      url: data["url"],
      primary_color: data["primary_color"],
      logo_url: data["logo_url"]
    }
  end

  def account_payload(data)
    {
      account_id: data["id"],
      name: data["name"],
      type: data["type"],
      subtype: data["type"],
      mask: data["account_number"]&.last(4),
      currency: data["currency"],
      current_balance: data["current_balance"],
      available_balance: data["available_balance"]
    }
  end


  def transactions_payload(data)
    data = data.as_json.deep_symbolize_keys
    data = {
      added: data[:added]&.map do |t|
        {
          transaction_id: t[:id],
          merchant_id: nil,
          merchant_name: nil,
          description: t[:narration],
          amount: t[:type] == "credit" ? -t[:amount] : t[:amount],
          date: t[:date],
          iso_currency_code: nil,
          category: t[:category],
          website: nil,
          logo_url: nil
        }
      end,
      modified: [],
      removed: []
    }
    data
  end
end
