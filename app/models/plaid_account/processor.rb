class PlaidAccount::Processor
  include PlaidAccount::TypeMappable

  attr_reader :external_account

  def initialize(external_account)
    @external_account = external_account
  end

  # Each step represents a different external API endpoint / "product"
  #
  # Processing the account is the first step and if it fails, we halt the entire processor
  # Each subsequent step can fail independently, but we continue processing the rest of the steps
  def process
    process_account!
    process_transactions
    process_investments
    process_liabilities
  end

  private
    def family
      external_account.external_item.family
    end

    # Shared securities reader and resolver
    def security_resolver
      @security_resolver ||= PlaidAccount::Investments::SecurityResolver.new(external_account)
    end

    def process_account!
      PlaidAccount.transaction do
        account = family.accounts.find_or_initialize_by(
          external_account_id: external_account.id
        )

        # Name and subtype are the only attributes a user can override for external accounts
        account.enrich_attributes(
          {
            name: external_account.name,
            subtype: map_subtype(external_account.external_type, external_account.external_subtype)
          },
          source: "external"
        )

        account.assign_attributes(
          accountable: map_accountable(external_account.external_type),
          balance: balance_calculator.balance,
          currency: external_account.currency,
          cash_balance: balance_calculator.cash_balance
        )

        account.save!

        # Create or update the current balance anchor valuation for event-sourced ledger
        # Note: This is a partial implementation. In the future, we'll introduce HoldingValuation
        # to properly track the holdings vs. cash breakdown, but for now we're only tracking
        # the total balance in the current anchor. The cash_balance field on the account model
        # is still being used for the breakdown.
        account.set_current_balance(balance_calculator.balance)
      end
    end

    def process_transactions
      PlaidAccount::Transactions::Processor.new(external_account).process
    rescue => e
      report_exception(e)
    end

    def process_investments
      PlaidAccount::Investments::TransactionsProcessor.new(external_account, security_resolver: security_resolver).process
      PlaidAccount::Investments::HoldingsProcessor.new(external_account, security_resolver: security_resolver).process
    rescue => e
      report_exception(e)
    end

    def process_liabilities
      case [ external_account.external_type, external_account.external_subtype ]
      when [ "credit", "credit card" ]
        PlaidAccount::Liabilities::CreditProcessor.new(external_account).process
      when [ "loan", "mortgage" ]
        PlaidAccount::Liabilities::MortgageProcessor.new(external_account).process
      when [ "loan", "student" ]
        PlaidAccount::Liabilities::StudentLoanProcessor.new(external_account).process
      end
    rescue => e
      report_exception(e)
    end

    def balance_calculator
      if external_account.external_type == "investment"
        @balance_calculator ||= PlaidAccount::Investments::BalanceCalculator.new(external_account, security_resolver: security_resolver)
      else
        balance = external_account.current_balance || external_account.available_balance || 0

        # We don't currently distinguish "cash" vs. "non-cash" balances for non-investment accounts.
        OpenStruct.new(
          balance: balance,
          cash_balance: balance
        )
      end
    end

    def report_exception(error)
      Sentry.capture_exception(error) do |scope|
        scope.set_tags(external_account_id: external_account.id)
      end
    end
end
