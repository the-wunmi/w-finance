class ApplicationMailer < ActionMailer::Base
  default from: email_address_with_name(ENV.fetch("EMAIL_SENDER", "sender@doubleu.local"), "DoubleU Finance")
  layout "mailer"
end
