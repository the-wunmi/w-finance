class Provider::MonoAdapter
  def item_payload(data)
    {
      available_products: data["meta"]["retrieved_data"] || [ "balance", "transactions" ],
      billed_products: data["meta"]["retrieved_data"] || [ "balance", "transactions" ]
    }
  end

  def institution_payload(data)
    {
      name: data["name"],
      institution_id: data["bank_code"],
      url: nil,
      primary_color: nil
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
      current_balance: data["balance"] / 100.0,
      available_balance: data["balance"] / 100.0
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
          amount: t[:type] == "credit" ? -t[:amount] / 100.0 : t[:amount] / 100.0,
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
