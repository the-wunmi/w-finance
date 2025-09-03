class BankConnectors::BaseConnector
  attr_reader :bank_provider

  def initialize(bank_provider)
    @bank_provider = bank_provider
  end

  def authenticate(credentials)
    raise NotImplementedError, "Subclasses must implement #authenticate"
  end

  def fetch_accounts(connection_data)
    raise NotImplementedError, "Subclasses must implement #fetch_accounts"
  end

  def fetch_transactions(connection_data, account_id)
    raise NotImplementedError, "Subclasses must implement #fetch_transactions"
  end

  def disconnect(connection_data)
  end

  protected

    def validate_credentials(credentials)
      bank_provider.credential_field_definitions.each do |field|
        value = credentials[field.name]

        if field.required && value.blank?
          raise ValidationError, "#{field.label} is required"
        end

        if field.validation && !validate_field(value, field.validation)
          raise ValidationError, "Invalid #{field.label.downcase}"
        end
      end
    end

    def http_client
      @http_client ||= Faraday.new do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
        f.options.timeout = 30
        f.options.open_timeout = 10
      end
    end

  private

    def validate_field(value, validation)
      case validation["type"]
      when "regex"
        Regexp.new(validation["pattern"]).match?(value)
      when "length"
        value.length >= (validation["min"] || 0) &&
        value.length <= (validation["max"] || Float::INFINITY)
      else
        true
      end
    end

    class ValidationError < StandardError; end
    class AuthenticationError < StandardError; end
    class ConnectionError < StandardError; end
    class ItemLoginRequiredError < StandardError; end
end
