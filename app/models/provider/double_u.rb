class Provider::DoubleU
  def get_link_token(user_id:, webhooks_url:, redirect_url:, accountable_type: nil, access_token: nil)
    SecureRandom.hex(16)
  end

  def exchange_public_token(bank_connection_id)
    connection = BankConnection.find(bank_connection_id)

    OpenStruct.new(
      item_id: connection.id,
    )
  end

  def get_item(external_item)
    connection = BankConnection.find(external_item.external_id)
    bank_provider = connection.bank_provider

    {
      "institution_id" => bank_provider.bank_id,
      "available_products" => [ "balance", "transactions" ]
    }
  end

  def remove_item(external_item)
    connection = BankConnection.find(external_item.external_id)
    bank_provider = connection.bank_provider

    connector = BankConnectorRegistry.get_connector(bank_provider)
    connector.disconnect(JSON.parse(connection.session_token))

    nil
  end

  def get_item_accounts(external_item)
    connection = BankConnection.find(external_item.external_id)
    bank_provider = connection.bank_provider

    connector = BankConnectorRegistry.get_connector(bank_provider)

    begin
      connector.fetch_accounts(JSON.parse(connection.session_token))
    rescue BankConnectors::BaseConnector::AuthenticationError
      begin
        perform_reauthentication(connection, connector)
        connector.fetch_accounts(JSON.parse(connection.session_token))
      rescue BankConnectors::BaseConnector::AuthenticationError
        raise BankConnectors::BaseConnector::ItemLoginRequiredError.new("Multiple authentication failures - user intervention required")
      end
    end
  end

  def get_transactions(external_item, account_id, next_cursor: nil)
    connection = BankConnection.find(external_item.external_id)
    bank_provider = connection.bank_provider

    connector = BankConnectorRegistry.get_connector(bank_provider)

    begin
      transactions = connector.fetch_transactions(JSON.parse(connection.session_token), account_id, since_id: next_cursor)
    rescue BankConnectors::BaseConnector::AuthenticationError
      begin
        perform_reauthentication(connection, connector)
        transactions = connector.fetch_transactions(JSON.parse(connection.session_token), account_id, since_id: next_cursor)
      rescue BankConnectors::BaseConnector::AuthenticationError
        raise BankConnectors::BaseConnector::ItemLoginRequiredError.new("Multiple authentication failures - user intervention required")
      end
    end

    transactions = transactions.sort_by { |txn| DateTime.parse(txn["date"]) }.reverse

    if next_cursor
      transactions = transactions[0...transactions.index { |t| t["id"] == next_cursor }]
    end

    TransactionSyncResponse.new(
      added: transactions,
      modified: [],
      removed: [],
      cursor: transactions.first&.dig("id")
    )
  end

  def get_item_investments(external_item, account_id, start_date: nil, end_date: Date.current)
    nil
  end

  def get_item_liabilities(external_item, account_id)
    nil
  end

  def get_institution(item_data)
    bank_provider = BankProvider.find_by(bank_id: item_data["institution_id"])

    {
      "name" => bank_provider&.display_name || bank_provider&.name || "Unknown Bank",
      "institution_id" => item_data["institution_id"],
      "url" => bank_provider&.website,
      "primary_color" => bank_provider&.primary_color,
      "logo_url" => bank_provider&.logo_url
    }
  end

  private
    TransactionSyncResponse = Struct.new(:added, :modified, :removed, :cursor, keyword_init: true)

    def perform_reauthentication(connection, connector)
      credentials = JSON.parse(connection.credentials)
      session_token = JSON.parse(connection.session_token)

      auth_result = connector.authenticate(credentials, session_token: session_token)

      if auth_result[:authenticated]
        connection.update!(
          session_token: (auth_result[:session_token] || {}).to_json,
          session_expires_at: auth_result[:session_expires_at],
          status: :connected
        )
      else
        raise BankConnectors::BaseConnector::ItemLoginRequiredError.new("Reauthentication failed")
      end
    end
end
