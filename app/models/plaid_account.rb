class PlaidAccount < ApplicationRecord
  belongs_to :external_item

  has_one :account, dependent: :destroy

  validates :name, :external_type, :currency, presence: true
  validate :has_balance

  def upsert_external_snapshot!(account_snapshot)
    assign_attributes(
      current_balance: account_snapshot.balances.current,
      available_balance: account_snapshot.balances.available,
      currency: account_snapshot.balances.iso_currency_code,
      external_type: account_snapshot.type,
      external_subtype: account_snapshot.subtype,
      name: account_snapshot.name,
      mask: account_snapshot.mask,
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

  private
    # External provider guarantees at least one of these.  This validation is a sanity check for that guarantee.
    def has_balance
      return if current_balance.present? || available_balance.present?
      errors.add(:base, "External account must have either current or available balance")
    end
end
