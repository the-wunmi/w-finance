class BankConnection < ApplicationRecord
  belongs_to :family
  belongs_to :bank_provider

  enum :status, { pending: "pending", requires_mfa: "requires_mfa", connected: "connected", failed: "failed" }, default: :pending

  encrypts :credentials
  encrypts :session_token

  def requires_mfa?
    status == "requires_mfa"
  end
end
