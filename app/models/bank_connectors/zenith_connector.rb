class BankConnectors::ZenithConnector < BankConnectors::BaseConnector
  def initialize(bank_provider)
    super
  end

  def authenticate(credentials, session_token: nil)
    validate_credentials(credentials)

    login_id = credentials["login_id"].to_s
    password = credentials["password"].to_s

    device_id = session_token&.[]("device_id") || SecureRandom.hex(8)

    login_body = generate_body({
      "loginID" => login_id,
      "deviceID" => device_id,
      "password" => password
    })

    encrypted_body = encrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id, login_body)

    response = client.post("customer/authenticate", encrypted_body) do |req|
      req.headers["Content-Type"] = "text/plain"
      req.headers["appVersion"] = "2.12.28"
      req.headers["deviceId"] = device_id
    end

    handle_response_error(response)

    decrypted_data = decrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id, response.body)
    account_data = JSON.parse(decrypted_data)

    unless account_data["code"] == 0
      message = account_data["description"] || "Authentication failed"
      raise AuthenticationError, message
    end

    {
      authenticated: true,
      requires_mfa: false,
      session_token: {
        "session_id" => account_data["sessionID"],
        "device_id" => device_id,
        "account_data" => account_data
      },
      session_expires_at: account_data["sessionTimeoutInSeconds"].seconds.from_now
    }
  end

  def fetch_accounts(session_token)
    account_data = session_token["account_data"]
    accounts = []

    account_data["accounts"]&.each do |acc|
      accounts << {
        "id" => acc["accountNumber"],
        "name" => acc["accountName"],
        "type" => map_account_type(acc["accountType"]),
        "account_number" => acc["accountNumber"],
        "currency" => acc["currency"],
        "available_balance" => acc["availableBalance"].to_f,
        "current_balance" => acc["bookBalance"].to_f
      }
    end

    accounts
  end

  def fetch_transactions(session_token, account_id, start_date: nil, end_date: nil, since_id: nil)
    device_id = session_token["device_id"]
    session_id = session_token["session_id"]
    all_transactions = []

    date_ranges = fetch_date_ranges(start_date, end_date)

    date_ranges.each_with_index do |date_range, i|
      batch_start_date = date_range[:start_date]
      batch_end_date = date_range[:end_date]

      transaction_body = generate_body({
        "accountNumber" => account_id,
        "startDate" => batch_start_date.strftime("%d-%m-%Y"),
        "endDate" => batch_end_date.strftime("%d-%m-%Y")
      })

      encrypted_body = encrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id, transaction_body)

      response = client.post("account/transactions/search", encrypted_body) do |req|
        req.headers["Content-Type"] = "text/plain"
        req.headers["appVersion"] = "2.12.28"
        req.headers["deviceId"] = device_id
        req.headers["sessionId"] = session_id
      end

      handle_response_error(response)

      decrypted_data = decrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id, response.body)
      transaction_data = JSON.parse(decrypted_data)

      unless transaction_data["code"] == 0
        raise ConnectionError, transaction_data["description"] || "Failed to fetch transactions"
      end

      transactions = transaction_data["transactions"] || []
      all_transactions.concat(transactions)

      should_break = false

      if since_id
        filtered_transactions = []
        transactions.each do |t|
          if t["tranId"] == since_id
            should_break = true
            break
          end

          filtered_transactions << t
        end
        all_transactions.concat(filtered_transactions)
      else
        all_transactions.concat(transactions)
      end

      break if should_break


      sleep(0.5) if i < (date_ranges.length - 1)
    end

    all_transactions.uniq { |t| t["tranId"] }.map do |t|
      {
        "id" => t["tranId"],
        "amount" => t["amount"].to_f.abs,
        "date" => t["date"],
        "narration" => t["narration"],
        "type" => t["type"]&.downcase === "c" ? "credit" : "debit",
        "balance" => t["closingBalance"].to_f,
        "category" => nil,
        "currency" => t["currency"],
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

    ENCRYPTION_KEY = ENV["ZENITH_ENCRYPTION_KEY"]
    ENCRYPTION_IV = ENV["ZENITH_ENCRYPTION_IV"]

    def generate_body(params)
      params_with_markers = { "start" => "" }.merge(params).merge({ "end" => "" })
      keys = []
      params_with_markers.each do |key, value|
        keys << "#{key}=#{value}"
      end
      keys.join("&")
    end

    def generate_key(str, device_id)
      salt = [ str ].pack("H*")
      OpenSSL::PKCS5.pbkdf2_hmac(device_id, salt, 23, 32, OpenSSL::Digest::SHA1.new)
    end

    def encrypt(str, iv, device_id, text)
      key = generate_key(str, device_id)
      iv_bytes = [ iv ].pack("H*")

      cipher = OpenSSL::Cipher.new("AES-256-CBC")
      cipher.encrypt
      cipher.key = key
      cipher.iv = iv_bytes

      encrypted = cipher.update(text) + cipher.final
      Base64.strict_encode64(encrypted)
    end

    def decrypt(str, iv, device_id, encrypted_data)
      key = generate_key(str, device_id)
      iv_bytes = [ iv ].pack("H*")

      cipher = OpenSSL::Cipher.new("AES-256-CBC")
      cipher.decrypt
      cipher.key = key
      cipher.iv = iv_bytes

      encrypted_bytes = Base64.decode64(encrypted_data)
      cipher.update(encrypted_bytes) + cipher.final
    end

    def map_account_type(zenith_type)
      case zenith_type&.downcase
      when "savings", "save"
        "savings"
      when "current", "curr"
        "checking"
      when "fixed", "fd"
        "fixed_deposit"
      else
        "other"
      end
    end

    def handle_response_error(response)
      unless response.success?
        raise ZenithApiError.new("Zenith API error: #{response.status} - #{response.body}")
      end
    end

    def provider_headers
      cfg = bank_provider.connection_config || {}
      headers = cfg["headers"]
      headers.is_a?(Hash) ? headers : {}
    end

    def fetch_date_ranges(start_date, end_date)
      one_year_ago = Date.current - 1.year
      current_date = Date.current

      start_date ||= one_year_ago
      end_date ||= current_date

      actual_start_date = [ Date.parse(start_date.to_s), one_year_ago ].max
      actual_end_date = [ Date.parse(end_date.to_s), current_date ].min

      return [] if actual_start_date > actual_end_date

      date_ranges = []
      current_batch_start = actual_start_date

      while current_batch_start <= actual_end_date
        current_batch_end = [ current_batch_start + 3.months - 1.day, actual_end_date ].min

        date_ranges << {
          start_date: current_batch_start,
          end_date: current_batch_end
        }

        current_batch_start = current_batch_end + 1.day
      end

      date_ranges.reverse
    end

    def client
      @client ||= Faraday.new(url: "https://zmobile.zenithbank.com/zenith/api/") do |f|
        provider_headers.each { |k, v| f.headers[k] = v }
        f.adapter Faraday.default_adapter
        f.options.timeout = 30
        f.options.open_timeout = 10
      end
    end

    class ZenithApiError < StandardError; end
end
