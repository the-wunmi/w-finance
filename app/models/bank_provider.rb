class BankProvider < ApplicationRecord
  validates :bank_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :country_code, presence: true, length: { is: 2 }

  scope :active, -> { where(active: true) }
  scope :for_country, ->(country) { where(country_code: country.upcase) }
  scope :by_name, -> { order(:name) }

  def credential_field_definitions
    @credential_field_definitions ||= (credential_fields || []).map do |field|
      CredentialField.new(field)
    end
  end

  def mfa_field_definitions
    @mfa_field_definitions ||= (mfa_config || []).map do |field|
      MfaField.new(field)
    end
  end

  class CredentialField
    include ActiveModel::Model

    attr_accessor :name, :label, :type, :required, :placeholder, :validation, :help_text, :options

    def initialize(attributes = {})
      attributes.each { |k, v| public_send("#{k}=", v) if respond_to?("#{k}=") }
    end

    def select_field?
      type == "select" && options.present?
    end

    def password_field?
      type == "password"
    end
  end

  class MfaField
    include ActiveModel::Model

    attr_accessor :name, :label, :type, :placeholder, :help_text, :validation

    def initialize(attributes = {})
      attributes.each { |k, v| public_send("#{k}=", v) if respond_to?("#{k}=") }
    end
  end
end
