class ExternalAccount < ApplicationRecord
  belongs_to :external_item

  has_one :account, dependent: :destroy

  validates :name, :external_type, :currency, presence: true
  validate :has_balance

  def upsert_external_snapshot!(account_snapshot)
    payload = Provider::DataProviderAdapter.new(provider).account_payload(account_snapshot)

    assign_attributes(
      current_balance: payload[:current_balance],
      available_balance: payload[:available_balance],
      currency: payload[:currency],
      external_type: payload[:type],
      external_subtype: payload[:subtype],
      name: payload[:name],
      mask: payload[:mask],
      raw_payload: account_snapshot
    )

    save!
  end

  def upsert_transactions_snapshot!(transactions_snapshot)
    assign_attributes(
      raw_transactions_payload: transactions_snapshot
    )

    save!
  end

  def upsert_investments_snapshot!(investments_snapshot)
    assign_attributes(
      raw_investments_payload: investments_snapshot
    )

    save!
  end

  def upsert_liabilities_snapshot!(liabilities_snapshot)
    assign_attributes(
      raw_liabilities_payload: liabilities_snapshot
    )

    save!
  end

  def provider
    self.external_item.provider
  end

  def payload
    Provider::DataProviderAdapter.new(provider).account_payload(self.raw_payload)
  end

  def transactions_payload
    Provider::DataProviderAdapter.new(provider).transactions_payload(self.raw_transactions_payload)
  end

  def investments_payload
    Provider::DataProviderAdapter.new(provider).investments_payload(self.raw_investments_payload)
  end

  def liabilities_payload
    Provider::DataProviderAdapter.new(provider).liabilities_payload(self.raw_liabilities_payload)
  end

  private
    # External provider guarantees at least one of these.  This validation is a sanity check for that guarantee.
    def has_balance
      return if current_balance.present? || available_balance.present?
      errors.add(:base, "External account must have either current or available balance")
    end
end
