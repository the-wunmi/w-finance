class BankProviderSeeder
  def self.seed!
    banks_data.each do |bank_data|
      bank = BankProvider.find_or_initialize_by(bank_id: bank_data[:bank_id])
      bank.assign_attributes(bank_data)
      bank.save!
    end
  end

  private

    def self.banks_data
      [
        {
          bank_id: "piggyvest",
          name: "PiggyVest",
          display_name: "PiggyVest",
          country_code: "NG",
          website: "https://www.piggyvest.com",
          primary_color: "#0a2",
          logo_url: "https://logo.clearbit.com/piggyvest.com",
          credential_fields: [
            {
              name: "username",
              label: "Username",
              type: "text",
              required: true,
              placeholder: "Enter your username"
            },
            {
              name: "password",
              label: "Password",
              type: "password",
              required: true,
              placeholder: "Enter your password"
            }
          ],
          mfa_config: [],
          connection_config: {
            base_url: nil
          }
        },
        {
          bank_id: "zenith",
          name: "Zenith Bank Plc",
          display_name: "Zenith Bank",
          country_code: "NG",
          website: "https://www.zenithbank.com",
          primary_color: "#e31e24",
          logo_url: "https://logo.clearbit.com/zenithbank.com",
          credential_fields: [
            {
              name: "login_id",
              label: "Login ID",
              type: "text",
              required: true,
              placeholder: "Enter your login ID"
            },
            {
              name: "password",
              label: "Password",
              type: "password",
              required: true,
              placeholder: "Enter your password"
            }
          ],
          mfa_config: [],
          connection_config: {
            base_url: "https://zmobile.zenithbank.com/zenith/api/"
          }
        },
        {
          bank_id: "providus",
          name: "Providus Bank Limited",
          display_name: "Providus Bank",
          country_code: "NG",
          website: "https://www.providusbank.com",
          primary_color: "#0066cc",
          logo_url: "https://logo.clearbit.com/providusbank.com",
          credential_fields: [
            {
              name: "username",
              label: "Username",
              type: "text",
              required: true,
              placeholder: "Enter your username"
            },
            {
              name: "password",
              label: "Password",
              type: "password",
              required: true,
              placeholder: "Enter your password"
                          }
            ],
            mfa_config: [
              {
                name: "otp",
                label: "OTP Code",
                type: "text",
                placeholder: "Enter 4-digit OTP",
                help_text: "Enter the OTP sent to your registered phone number"
              }
            ],
            connection_config: {
              base_url: "https://app.providusbank.com/"
            }
        }
      ]
    end
end

BankProviderSeeder.seed!

puts "Bank providers seeded successfully"
