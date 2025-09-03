class BankConnectors::ProvidusConnector < BankConnectors::BaseConnector
  def initialize(bank_provider)
    super
  end

  def authenticate(credentials, session_token: nil)
    validate_credentials(credentials)

    login_id = credentials["username"].to_s
    password = credentials["password"].to_s
    device_model = session_token&.[]("device_model") || "Android"

    device_id = session_token&.[]("device_id") || SecureRandom.hex(8)
    rand = Random.rand.to_s

    login_body = {
      loginID: login_id,
      mpin: password,
      deviceId: device_id,
      deviceModel: device_model,
      institutionCD: "059"
    }.to_json

    encrypted_body = encrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id + rand, login_body)
    timestamp_encrypted = encrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id, rand)

    response = client.post("customer/authenticate", encrypted_body) do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["appVersion"] = "2.5.0"
      req.headers["deviceId"] = device_id
      req.headers["channel"] = "MOBILE"
      req.headers["institutioncd"] = "059"
      req.headers["ostype"] = "android"
      req.headers["timestamp"] = timestamp_encrypted
    end

    handle_response_error(response)

    decrypted_data = decrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id + rand, response.body)
    auth_data = JSON.parse(decrypted_data)

    case auth_data["code"]
    when 0
      session_id = auth_data.delete("sessionID")
      account_number = auth_data.delete("accountNumber")

      {
        authenticated: true,
        requires_mfa: false,
        session_token: {
          "session_id" => session_id,
          "device_id" => device_id,
          "account_number" => account_number
        },
        session_expires_at: 5.minutes.from_now
      }
    when 22
      devices = auth_data["devices"] || []
      last_used_device = devices.min_by do |device|
        begin
          Time.parse(device["lastLoginTime"])
        rescue
          Time.new(1900)
        end
      end

      unless last_used_device
        raise AuthenticationError, "No devices available for binding"
      end

      {
        authenticated: false,
        requires_mfa: true,
        session_token: {
          "device_id" => device_id,
          "device_model" => device_model,
          "last_device_id" => last_used_device["deviceID"],
          "username" => login_id,
          "password" => password
        }
      }
    else
      message = auth_data["description"] || "Authentication failed"
      raise AuthenticationError, message
    end
  end

  def fetch_accounts(session_token)
    device_id = session_token["device_id"]
    session_id = session_token["session_id"]
    account_number = session_token["account_number"]

    rand = Random.rand.to_s

    accounts_body = {
      accountNumber: account_number
    }.to_json

    encrypted_body = encrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id + rand, accounts_body)
    timestamp_encrypted = encrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id, rand)

    response = client.post("customer/accountsdetails", encrypted_body) do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["appVersion"] = "2.5.0"
      req.headers["deviceId"] = device_id
      req.headers["channel"] = "MOBILE"
      req.headers["institutioncd"] = "059"
      req.headers["ostype"] = "android"
      req.headers["timestamp"] = timestamp_encrypted
      req.headers["sessionid"] = session_id
    end

    handle_response_error(response)

    decrypted_data = decrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id + rand, response.body)
    accounts_data = JSON.parse(decrypted_data)

    unless accounts_data["code"] == 0
      raise ConnectionError, accounts_data["description"] || "Failed to fetch accounts"
    end

    accounts = []
    accounts_data["accounts"]&.each do |acc|
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

      rand = Random.rand.to_s

      transaction_body = {
        deviceId: device_id,
        accountNumber: account_id,
        startDate: batch_start_date.strftime("%Y-%m-%d"),
        endDate: batch_end_date.strftime("%Y-%m-%d")
      }.to_json

      encrypted_body = encrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id + rand, transaction_body)
      timestamp_encrypted = encrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id, rand)

      response = client.post("transaction/miniStatement", encrypted_body) do |req|
        req.headers["Content-Type"] = "application/json"
        req.headers["appVersion"] = "2.5.0"
        req.headers["deviceId"] = device_id
        req.headers["channel"] = "MOBILE"
        req.headers["institutioncd"] = "059"
        req.headers["ostype"] = "android"
        req.headers["timestamp"] = timestamp_encrypted
        req.headers["sessionid"] = session_id
        req.headers["sourceaccount"] = account_id
      end

      handle_response_error(response)

      decrypted_data = decrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id + rand, response.body)
      transaction_data = JSON.parse(decrypted_data)

      unless transaction_data["code"] == 0
        raise ConnectionError, transaction_data["description"] || "Failed to fetch transactions"
      end

      transactions = transaction_data["transactions"] || []
      should_break = false

      if since_id
        filtered_transactions = []
        transactions.each do |t|
          transaction_id = generate_transaction_id(account_id, t)

          if transaction_id == since_id
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

    all_transactions.uniq { |t| generate_transaction_id(account_id, t) }.map do |t|
      {
        "id" => generate_transaction_id(account_id, t),
        "amount" => t["amount"].to_f.abs,
        "date" => t["date"],
        "narration" => t["narration"],
        "type" => t["type"]&.upcase == "C" ? "credit" : "debit",
        "balance" => nil,
        "category" => nil,
        "currency" => nil,
        "country" => nil,
        "latitude" => nil,
        "longitude" => nil
      }
    end
  end

  def verify_mfa(session_token, credentials, otp_code)
    device_id = session_token["device_id"]
    device_model = session_token["device_model"]
    last_device_id = session_token["last_device_id"]
    username = credentials["username"]

    rand = Random.rand.to_s

    bind_body = {
      otp: otp_code,
      deviceId: last_device_id,
      newDeviceId: device_id,
      newDeviceModel: device_model,
      newDeviceName: device_model,
      institutionCD: "059",
      accountNumber: username,
      replace: true
    }.to_json

    encrypted_body = encrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id + rand, bind_body)
    timestamp_encrypted = encrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id, rand)

    response = client.post("customer/bindDevice", encrypted_body) do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["appVersion"] = "2.5.0"
      req.headers["deviceId"] = device_id
      req.headers["channel"] = "MOBILE"
      req.headers["institutioncd"] = "059"
      req.headers["ostype"] = "android"
      req.headers["timestamp"] = timestamp_encrypted
    end

    handle_response_error(response)

    decrypted_data = decrypt(ENCRYPTION_KEY, ENCRYPTION_IV, device_id + rand, response.body)
    bind_data = JSON.parse(decrypted_data)

    unless bind_data["code"] == 0
      message = bind_data["description"] || "Device binding failed"
      raise AuthenticationError, message
    end

    authenticate(credentials, session_token: session_token)
  end

  def disconnect(connection_data)
    true
  end

  private

    ENCRYPTION_KEY = ENV["PROVIDUS_ENCRYPTION_KEY"]
    ENCRYPTION_IV = ENV["PROVIDUS_ENCRYPTION_IV"]

    def generate_transaction_id(account_id, transaction)
      Digest::SHA256.hexdigest("#{account_id}-#{transaction['date']}-#{transaction['amount']}-#{transaction['narration']}")
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

    def map_account_type(providus_type)
      case providus_type&.downcase
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
        if response.status == 500
          raise AuthenticationError.new("Session expired - reauthentication required")
        else
          raise ProvidusApiError.new("Providus API error: #{response.status} - #{response.body}")
        end
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
      @client ||= Faraday.new(url: "https://app.providusbank.com/") do |f|
        provider_headers.each { |k, v| f.headers[k] = v }
        f.adapter Faraday.default_adapter
        f.options.timeout = 30
        f.options.open_timeout = 10
      end
    end

    class ProvidusApiError < StandardError; end
end
