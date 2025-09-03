class BankCredentialsValidator
  include ActiveModel::Validations

  class InvalidCredentialsError < StandardError; end

  attr_reader :bank_provider, :credentials, :error_message

  def initialize(bank_provider:, credentials:)
    @bank_provider = bank_provider
    @credentials = credentials
    @error_message = nil
  end


  def validate_credential_fields?
    bank_provider.credential_field_definitions.each do |field|
      value = credentials[field.name]

      if field.required && value.blank?
        errors.add(field.name, "#{field.label} is required")
      end

      if value.present? && field.validation
        unless validate_field_format(value, field.validation)
          errors.add(field.name, "Invalid #{field.label.downcase}")
        end
      end
    end

    errors.empty?
  end

  def validate_with_bank_connector
    connector = BankConnectorRegistry.get_connector(bank_provider)
    result = connector.authenticate(sanitized_credentials)

    unless result[:authenticated] || result[:requires_mfa]
      raise InvalidCredentialsError, "Authentication failed"
    end

    result
  rescue BankConnectors::BaseConnector::AuthenticationError => e
    raise InvalidCredentialsError, e.message
  rescue BankConnectors::BaseConnector::ConnectionError => e
    raise InvalidCredentialsError, "Connection failed: #{e.message}"
  end

  def sanitized_credentials
    sanitized = {}
    bank_provider.credential_field_definitions.each do |field|
      sanitized[field.name] = credentials[field.name]
    end
    sanitized
  end

  private
    def validate_field_format(value, validation)
      case validation["type"]
      when "regex"
        Regexp.new(validation["pattern"]).match?(value)
      when "length"
        min_length = validation["min"] || 0
        max_length = validation["max"] || Float::INFINITY
        value.length >= min_length && value.length <= max_length
      else
        true
      end
    end
end
