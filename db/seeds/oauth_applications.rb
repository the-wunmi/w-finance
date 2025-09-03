# Create OAuth applications for DoubleU's first-party apps
# These are the only OAuth apps that will exist - external developers use API keys

# DoubleU iOS App
ios_app = Doorkeeper::Application.find_or_create_by(name: "DoubleU iOS") do |app|
  app.redirect_uri = "doubleuapp://oauth/callback"
  app.scopes = "read_accounts read_transactions read_balances"
  app.confidential = false # Public client (mobile app)
end

puts "Created OAuth applications:"
puts "iOS App - Client ID: #{ios_app.uid}"
puts ""
puts "External developers should use API keys instead of OAuth."
