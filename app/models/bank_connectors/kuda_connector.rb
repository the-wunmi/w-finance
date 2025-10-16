require_relative "../firestore_client"

class BankConnectors::KudaConnector < BankConnectors::BaseConnector
  def initialize(bank_provider)
    super
  end

  def authenticate(credentials, session_token: nil)
    validate_credentials(credentials)

    username = credentials["username"].to_s
    password = credentials["password"].to_s
    device_id = session_token&.[]("device_id") || "Chrome Mobile 119.0.0.0 on Google Nexus 5 (Android 6.0)"
    app_version = "2.0.125"

    random_key = generate_random_key
    encryption_key = rsa_encrypt(random_key)

    login_payload = {
      appVersion: app_version,
      os: 3,
      osVersion: device_id,
      macAddress: generate_mac_address,
      deviceId: "Android 6.0",
      deviceDetails: device_id,
      deviceName: device_id,
      localTime: Time.current.iso8601,
      isWeb: true,
      username: username,
      password: password
    }

    response = client.post("kuda-retail-onboardingms/api/v1/Login/InitiateWebLogin") do |req|
      req.headers["authorization"] = "Bearer"
      req.headers["encryptionkey"] = encryption_key
      req.headers["content-type"] = "application/json;charset=UTF-8"
      req.body = {
        data: aes_encrypt(login_payload.to_json, random_key)
      }
    end

    data = handle_response(response)

    unless data["status"]
      message = data["message"] || "Authentication failed"
      raise AuthenticationError, message
    end

    {
      authenticated: false,
      requires_mfa: true,
      session_token: {
        "username" => username,
        "password" => password,
        "device_id" => device_id,
        "random_key" => random_key
      },
      session_expires_at: 10.minutes.from_now
    }
  end

  def verify_mfa(session_token, credentials, otp_code)
    username = session_token["username"]
    password = session_token["password"]
    device_id = session_token["device_id"]
    random_key = session_token["random_key"]
    app_version = "2.0.125"

    encryption_key = rsa_encrypt(random_key)

    login_payload = {
      appVersion: app_version,
      os: 3,
      osVersion: device_id,
      macAddress: generate_mac_address,
      deviceId: "Android 6.0",
      deviceDetails: device_id,
      deviceName: device_id,
      localTime: Time.current.iso8601,
      isWeb: true,
      username: username,
      password: password,
      otp: otp_code
    }

    response = client.post("kuda-retail-onboardingms/api/v1/Login/WebLogin") do |req|
      req.headers["authorization"] = "Bearer"
      req.headers["encryptionkey"] = encryption_key
      req.headers["content-type"] = "application/json;charset=UTF-8"
      req.body = {
        data: aes_encrypt(login_payload.to_json, random_key)
      }
    end

    data = handle_response(response)

    unless data.dig("data", "access_token")
      message = data["message"] || "Authentication failed"
      raise AuthenticationError, message
    end

    {
      authenticated: true,
      requires_mfa: false,
      session_token: {
        "token" => data["data"]["access_token"],
        "customer_id" => username,
        "device_id" => device_id,
      },
      session_expires_at: (data["data"]["expires_in"]&.to_i || 3600).seconds.from_now
    }
  end

  def fetch_accounts(session_token)
    token = session_token["token"]

    response = client.get("retailaccounts/api/v1/Accounts") do |req|
      req.headers["authorization"] = "Bearer #{token}"
    end

    data = handle_response(response)
    accounts = data["data"]["results"] || []

    accounts.map do |account|
      balance_response = client.get("retailaccounts/api/v1/Accounts/#{account['id']}/balance") do |req|
        req.headers["authorization"] = "Bearer #{token}"
      end

      balance_data = handle_response(balance_response)
      balance_info = balance_data["data"] || {}

      {
        "id" => account["id"],
        "name" => account["accountName"],
        "type" => "savings",
        "account_number" => account["accountNumber"],
        "currency" => account["currency"],
        "available_balance" => balance_info["availableBalance"]&.to_f || 0.0,
        "current_balance" => balance_info["balance"]&.to_f || 0.0
      }
    end
  end

  def fetch_transactions(session_token, account_id, start_date: nil, end_date: nil, since_id: nil)
    token = session_token["token"]

    static_data = fetch_static_transaction_data
    tag_icons = build_tag_icon_mapping(static_data)

    firebase_client = initialize_firebase

    query = firebase_client.collection("retail_accounts/#{account_id}/transactions").order("Timestamp", :desc).limit(1000)
    
    docs = query.get

    transactions = []
    docs.each_with_index do |doc, index|
      data = doc.data

      type = data["TransactionType"] == "C" ? "credit" : "debit"
      if data["IsReversal"]
        type = type == "credit" ? "debit" : "credit"
      end

      amount = data["Amount"].to_f / 100

      timestamp = data["Timestamp"]
      date = nil
      if timestamp && timestamp.is_a?(Time)
        date = timestamp.strftime("%Y-%m-%d %H:%M:%S")
      end

      merchant = (
        if data["Merchant"].present? && !data["Merchant"].downcase.include?("unknown")
          {
            "id" => Digest::SHA256.hexdigest("#{data["Merchant"]}"),
            "name" => data["Merchant"]
          }
        end
      )

      narration = data["Narration"].to_s
      extra_label = data["Name"].presence || data["Merchant"].presence
      if extra_label.present? && !narration.downcase.include?(extra_label.to_s.downcase)
        narration = "#{narration} - #{extra_label}"
      end

      transactions << {
        "id" => data["Id"],
        "amount" => amount,
        "date" => date,
        "narration" => narration,
        "type" => type,
        "category" => nil,
        "balance" => nil,
        "currency" => nil,
        "country" => nil,
        "latitude" => nil,
        "longitude" => nil,
        "merchant_name" => merchant&.dig("name"),
        "merchant_id" => merchant&.dig("id"),
        "logo_url" => tag_icons[data["TagId"]&.to_s]
      }
    end

    transactions
  end

  def disconnect(connection_data)
    true
  end

  private

    def fetch_static_transaction_data
      conn = Faraday.new do |f|
        f.response :json
        f.adapter Faraday.default_adapter
      end

      response = conn.get('https://d38v990enafbk6.cloudfront.net/static/transaction-static-data.json')
      
      unless response.success?
        raise ConnectionError, "Failed to fetch static transaction data: #{response.status}"
      end

      response.body
    end

    def build_tag_icon_mapping(static_data)
      tag_icons = {}
      
      return tag_icons unless static_data && static_data['tags']
      
      static_data['tags'].each do |tag|
        if tag['tagId'] && tag['iconUrl']
          tag_icons[tag['tagId']] = tag['iconUrl']
        end
      end
      
      tag_icons
    end

    def generate_random_key
      charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.="
      (0...15).map { charset[rand(charset.length)] }.join
    end

    def generate_mac_address
      "XX:XX:XX:XX:XX:XX".gsub(/X/) { "0123456789ABCDEF"[rand(16)] }
    end

    def rsa_encrypt(plaintext)
      public_key_pem = ENV["KUDA_PUBLIC_KEY"]&.gsub(/\\n/, "\n")&.strip
      raise ConnectionError, "KUDA_PUBLIC_KEY not configured" unless public_key_pem

      public_key = OpenSSL::PKey::RSA.new(public_key_pem)
      encrypted = public_key.public_encrypt(plaintext, OpenSSL::PKey::RSA::PKCS1_PADDING)
      Base64.strict_encode64(encrypted)
    end

    def aes_encrypt(string, key)
      salt = 'randomsalt'
  
      derived_key = OpenSSL::PKCS5.pbkdf2_hmac(
        key,
        salt,
        1000,
        32,
        OpenSSL::Digest::SHA1.new
      )
      
      iv = OpenSSL::PKCS5.pbkdf2_hmac(
        key,
        salt,
        1000,
        16,
        OpenSSL::Digest::SHA1.new
      )
      
      cipher = OpenSSL::Cipher.new('AES-256-CBC')
      cipher.encrypt
      cipher.key = derived_key
      cipher.iv = iv
      
      encrypted = cipher.update(string) + cipher.final
      
      base64_encrypted = Base64.strict_encode64(encrypted)
      decoded = Base64.strict_decode64(base64_encrypted)
      hex_string = decoded.unpack1('H*')
      
      Base64.strict_encode64([hex_string].pack('H*'))
    end

    def initialize_firebase
      firebase_config = ENV["KUDA_FIREBASE"]
      raise ConnectionError, "KUDA_FIREBASE not configured" unless firebase_config

      config = JSON.parse(firebase_config)
      FirestoreClient.new(credentials: config)
    end

    def handle_response(response)
      unless response.success?
        raise KudaApiError.new("Kuda API error: #{response.status} - #{response.body}")
      end
      response.body
    end

    def client
      base_url = ENV["KUDA_BASE_URL"]
      raise ConnectionError, "KUDA_BASE_URL not configured" unless base_url

      @client ||= Faraday.new(url: base_url) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
        f.options.timeout = 90
        f.options.open_timeout = 30
      end
    end

    class KudaApiError < StandardError; end
end
