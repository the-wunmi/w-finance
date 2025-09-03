class Banks::ConnectController < ApplicationController
  before_action :set_bank

  def create
    begin
      validator = BankCredentialsValidator.new(
        bank_provider: @bank,
        credentials: params.fetch(:credentials, {})
      )

      if validator.validate_credential_fields?
        connection = Current.family.bank_connections.create!(
          bank_provider: @bank,
          status: :pending,
          credentials: validator.sanitized_credentials.to_json
        )

        auth_result = validator.validate_with_bank_connector

        connection.update!(
          session_token: (auth_result[:session_token] || {}).to_json,
          session_expires_at: auth_result[:session_expires_at],
          status: auth_result[:requires_mfa] ? :requires_mfa : :connected
        )

        if connection.requires_mfa?
          redirect_to mfa_bank_connect_path(@bank, connection_id: connection.id)
        else
          finalize_connection!(connection)
        end
      else
        flash.now[:alert] = validator.error_message || validator.errors.full_messages.to_sentence
        render "banks/show", status: :unprocessable_entity
      end
    rescue BankCredentialsValidator::InvalidCredentialsError => e
      flash.now[:alert] = e.message
      render "banks/show", status: :unprocessable_entity
    end
  end

  def mfa
    @connection = Current.family.bank_connections.find_by!(id: params[:connection_id], bank_provider: @bank)
    @mfa_fields = @bank.mfa_field_definitions
  end

  def verify_mfa
    @connection = Current.family.bank_connections.find_by!(id: params[:connection_id], bank_provider: @bank)
    credentials = JSON.parse(@connection.credentials)
    session_token = JSON.parse(@connection.session_token)
    mfa_code = params[:mfa_code]

    verifier = BankMfaVerifier.new(
      bank_provider: @bank,
      session_token: session_token,
      credentials: credentials,
      mfa_code: mfa_code
    )

    auth_result = verifier.verify

    if auth_result
      @connection.update!(
        session_token: (auth_result[:session_token] || @connection[:session_token] || {}).to_json,
        session_expires_at: auth_result[:session_expires_at] || @connection[:session_expires_at],
      )
      finalize_connection!(@connection)
    else
      flash.now[:alert] = verifier.error_message
      @mfa_fields = @bank.mfa_field_definitions
      render :mfa, status: :unprocessable_entity
    end
  end

  def finalize_connection!(connection)
    connection.update!(status: :connected)
    @connection = connection
    render :finalize
  end

  private
    def set_bank
      @bank = BankProvider.find(params[:bank_id])
    end
end
