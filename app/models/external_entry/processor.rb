class ExternalEntry::Processor
  # external_transaction is the raw hash fetched from external API and converted to JSONB
  def initialize(external_transaction, external_account:, category_matcher:)
    @external_transaction = external_transaction
    @external_account = external_account
    @category_matcher = category_matcher
  end

  def process
    ExternalAccount.transaction do
      entry = account.entries.find_or_initialize_by(external_id: external_id) do |e|
        e.entryable = Transaction.new
      end

      entry.assign_attributes(
        amount: amount,
        currency: currency,
        date: date
      )

      entry.enrich_attribute(
        :name,
        name,
        source: "external"
      )

      if detailed_category
        matched_category = category_matcher.match(detailed_category)

        if matched_category
          entry.transaction.enrich_attribute(
            :category_id,
            matched_category.id,
            source: "external"
          )
        end
      end

      if merchant
        entry.transaction.enrich_attribute(
          :merchant_id,
          merchant.id,
          source: "external"
        )
      end
    end
  end

  private
    attr_reader :external_transaction, :external_account, :category_matcher

    def account
      external_account.account
    end

    def external_id
      external_transaction["transaction_id"]
    end

    def name
      external_transaction["merchant_name"] || external_transaction["original_description"]
    end

    def amount
      external_transaction["amount"]
    end

    def currency
      external_transaction["iso_currency_code"]
    end

    def date
      external_transaction["date"]
    end

    def detailed_category
      external_transaction.dig("personal_finance_category", "detailed")
    end

    def merchant
      merchant_id = external_transaction["merchant_entity_id"]
      merchant_name = external_transaction["merchant_name"]

      return nil unless merchant_id.present? && merchant_name.present?

      ProviderMerchant.find_or_create_by!(
        source: "external",
        name: merchant_name,
      ) do |m|
        m.provider_merchant_id = merchant_id
        m.website_url = external_transaction["website"]
        m.logo_url = external_transaction["logo_url"]
      end
    end
end
