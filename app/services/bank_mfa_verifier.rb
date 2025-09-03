class BankMfaVerifier
  attr_reader :bank_provider, :session_token, :credentials, :mfa_code, :error_message

  def initialize(bank_provider:, session_token:, credentials:, mfa_code:)
    @bank_provider = bank_provider
    @session_token = session_token
    @credentials = credentials.with_indifferent_access
    @mfa_code = mfa_code
    @error_message = nil
  end

  def verify
    return nil if mfa_code.blank?

    connector = BankConnectorRegistry.get_connector(bank_provider)

    result = connector.verify_mfa(session_token, credentials, mfa_code)

    if result[:authenticated]
      result
    else
      @error_message = result[:error] || "Invalid verification code"
      nil
    end
  rescue => e
    Rails.logger.error "MFA verification error: #{e.message}"
    @error_message = "MFA verification failed"
    nil
  end
end
