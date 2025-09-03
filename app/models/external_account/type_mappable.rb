module ExternalAccount::TypeMappable
  extend ActiveSupport::Concern

  UnknownAccountTypeError = Class.new(StandardError)

  def map_accountable(external_type)
    accountable_class = TYPE_MAPPING.dig(
      external_type.to_sym,
      :accountable
    )

    unless accountable_class
      accountable_class = find_accountable_by_regex(external_type)
    end

    unless accountable_class
      raise UnknownAccountTypeError, "Unknown account type: #{external_type}"
    end

    accountable_class.new
  end

  def map_subtype(external_type, external_subtype)
    subtype = TYPE_MAPPING.dig(
      external_type.to_sym,
      :subtype_mapping,
      external_subtype
    )

    unless subtype
      subtype = extract_subtype_from_external_type(external_type, external_subtype)
    end

    subtype || "other"
  end

  private

    def find_accountable_by_regex(external_type)
      normalized_type = external_type.to_s.downcase

      case normalized_type
      when /deposit|checking|savings|cash|bank|current/
        Depository
      when /credit|card/
        CreditCard
      when /loan|mortgage|debt|student|auto|home_equity|line_of_credit/
        Loan
      when /investment|brokerage|401k|ira|roth|pension|retirement|mutual/
        Investment
      else
        OtherAsset
      end
    end

    def extract_subtype_from_external_type(external_type, external_subtype)
      combined_text = "#{external_type} #{external_subtype}".downcase

      case combined_text
      when /savings/
        "savings"
      when /checking/
        "checking"
      when /hsa|health/
        "hsa"
      when /cd|certificate/
        "cd"
      when /money.?market/
        "money_market"

      when /credit.?card/
        "credit_card"

      when /mortgage/
        "mortgage"
      when /student/
        "student"
      when /auto(?!.*investment)/  # Avoid matching auto investment accounts
        "auto"

      when /brokerage/
        "brokerage"
      when /pension/
        "pension"
      when /retirement/
        "retirement"
      when /401k/
        "401k"
      when /roth.?401k/
        "roth_401k"
      when /529/
        "529_plan"
      when /mutual.?fund/
        "mutual_fund"
      when /roth.?ira|roth(?!.*401k)/
        "roth_ira"
      when /ira(?!.*roth)/
        "ira"
      when /angel/
        "angel"

      else
        nil
      end
    end

    # External Account Types -> Accountable Types
    # Based on external provider account type schema
    TYPE_MAPPING = {
      depository: {
        accountable: Depository,
        subtype_mapping: {
          "checking" => "checking",
          "savings" => "savings",
          "hsa" => "hsa",
          "cd" => "cd",
          "money market" => "money_market"
        }
      },
      credit: {
        accountable: CreditCard,
        subtype_mapping: {
          "credit card" => "credit_card"
        }
      },
      loan: {
        accountable: Loan,
        subtype_mapping: {
          "mortgage" => "mortgage",
          "student" => "student",
          "auto" => "auto",
          "business" => "business",
          "home equity" => "home_equity",
          "line of credit" => "line_of_credit"
        }
      },
      investment: {
        accountable: Investment,
        subtype_mapping: {
          "brokerage" => "brokerage",
          "pension" => "pension",
          "retirement" => "retirement",
          "401k" => "401k",
          "roth 401k" => "roth_401k",
          "529" => "529_plan",
          "hsa" => "hsa",
          "mutual fund" => "mutual_fund",
          "roth" => "roth_ira",
          "ira" => "ira"
        }
      },
      other: {
        accountable: OtherAsset,
        subtype_mapping: {}
      }
    }
end
