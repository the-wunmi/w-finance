class BankConnectors::PiggyvestConnector < BankConnectors::BaseConnector
  def initialize(bank_provider)
    super
  end

  def authenticate(credentials, session_token: nil)
    validate_credentials(credentials)

    username = credentials["username"].to_s
    password = credentials["password"].to_s

    key = ENV["PIGGYVEST_ENCRYPTION_KEY"]
    device_id = session_token&.[]("device_id") || SecureRandom.uuid.upcase

    response = client.post("auth/login") do |req|
      req.headers["device"] = { uniqueId: device_id }.to_json
      req.body = {
        identifier: encrypt(username, key+":"+device_id),
        password: encrypt(password, key+":"+device_id),
        country: "NG"
      }
    end

    data = handle_response(response)

    unless data.dig("status")
      message = data["message"].to_s.split(".").first.presence || "Authentication failed"
      raise AuthenticationError, message
    end

    {
      authenticated: true,
      requires_mfa: false,
      session_token: { "type" => data["data"]["type"], "token" => data["data"]["accessToken"], "device_id" => device_id },
      session_expires_at: data["data"]["expiresIn"].seconds.from_now
    }
  end

  def fetch_accounts(session_token)
    accounts = []
    accounts << fetch_account(session_token, type: "flexdollar")
    accounts << fetch_account(session_token, type: "flexnaira")
    accounts << fetch_account(session_token, type: "piggybank")
    accounts
  end

  def fetch_account(session_token, type:)
    response = client.get("app/#{type}/page") do |req|
      req.headers["Authorization"] = "#{session_token["type"]} #{session_token["token"]}"
      req.headers["device"] = { uniqueId: session_token["device_id"] }.to_json
    end

    data = handle_response(response)

    acc = data["data"]["walletInfo"]

    amount = parse_amount(acc["balanceText"])

    {
      "id" => type,
      "name" => type.titleize,
      "type" => "savings",
      "account_number" => "",
      "currency" => amount["currency"],
      "current_balance" => amount["amount"],
      "available_balance" => amount["amount"]
    }
  end

  def fetch_transactions(session_token, account_id, start_date: Date.current - 1.year, end_date: Date.current, since_id: nil)
    all_transactions = []
    page = 0
    page_size = 1000

    loop do
      response = client.get("app/#{account_id}/transactions/#{page_size}/#{page}") do |req|
        req.headers["Authorization"] = "#{session_token["type"]} #{session_token["token"]}"
        req.headers["device"] = { uniqueId: session_token["device_id"] }.to_json
      end

      data = handle_response(response)
      transactions = data["data"]["list"] || []

      break if transactions.empty?

      transactions_in_range = []
      should_break = false

      transactions.each do |transaction|
        if since_id && transaction["id"] == since_id
          should_break = true
          break
        end

        transaction_date = Date.parse(transaction["created_at"])

        if transaction_date < start_date
          should_break = true
          break
        end

        if transaction_date >= start_date && transaction_date <= end_date
          transactions_in_range << transaction
        end
      end

      all_transactions.concat(transactions_in_range)

      break if should_break

      page += 1
    end

    all_transactions.map do |t|
      amount = parse_amount(t["rawAmount"])
      {
        "id" => t["id"],
        "amount" => amount["amount"],
        "date" => t["created_at"],
        "narration" => t["description"],
        "type" => t["outward"] ? "debit" : "credit",
        "balance" => parse_amount(t["rawBalance"])["amount"],
        "category" => nil,
        "currency" => amount["currency"],
        "country" => nil,
        "latitude" => nil,
        "longitude" => nil
      }
    end
  end

  def disconnect(connection_data)
    true
  end

  private

    def parse_amount(amount_text)
      match = amount_text.match(/(\p{Sc})\s*([\d,]+(?:\.\d+)?)/u)
      raise ConnectionError, "Unable to parse amount: #{amount_text}" unless match
      currency_symbol = match[1]
      numeric_value = match[2].to_s.gsub(",", "")
      if currency_symbol == "$"
        currency_code = "USD"
      else
        currency_matches = Money::Currency.all_instances.select { |c| c.symbol == currency_symbol }
        raise ConnectionError, "Unknown or ambiguous currency symbol: #{currency_symbol}" unless currency_matches.length == 1
        currency_code = currency_matches.first.iso_code
      end
      {
        "amount" => numeric_value.to_f,
        "currency" => currency_code
      }
    end

    def handle_response(response)
      unless response.success?
        raise PiggyvestApiError.new("PiggyVest API error: #{response.status} - #{response.body}")
      end
      response.body
    end

    def provider_headers
      cfg = bank_provider.connection_config || {}
      headers = cfg["headers"]
      headers.is_a?(Hash) ? headers : {}
    end

    def encrypt(plaintext, passphrase)
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.encrypt

      salt = OpenSSL::Random.random_bytes(8)

      derived = evp_bytes_to_key(passphrase, salt, 32, 16)

      cipher.key = derived[:key]
      cipher.iv = derived[:iv]

      encrypted = cipher.update(plaintext) + cipher.final

      salted_msg = "Salted__" + salt + encrypted
      Base64.strict_encode64(salted_msg)
    end

    def decrypt(encrypted_data, passphrase)
      data = Base64.decode64(encrypted_data)

      salt = data[8, 8]
      encrypted = data[16..-1]

      derived = evp_bytes_to_key(passphrase, salt, 32, 16)

      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key = derived[:key]
      cipher.iv = derived[:iv]

      cipher.update(encrypted) + cipher.final
    end

    def evp_bytes_to_key(passphrase, salt, key_len, iv_len)
      d = d_i = ""
      while d.length < (key_len + iv_len)
        d_i = Digest::MD5.digest(d_i + passphrase + salt)
        d += d_i
      end

      {
        key: d[0, key_len],
        iv: d[key_len, iv_len]
      }
    end

    def client
      @client ||= Faraday.new(url: "https://api.piggyvest.com/v5/") do |f|
        provider_headers.each { |k, v| f.headers[k] = v }
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end
    end

    class PiggyvestApiError < StandardError; end
end
