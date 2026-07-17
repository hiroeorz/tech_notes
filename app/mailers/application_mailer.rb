class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM_ADDRESS").presence || raise(KeyError, "MAILER_FROM_ADDRESS must be set")
  layout "mailer"
end
