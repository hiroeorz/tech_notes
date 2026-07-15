class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM_ADDRESS", "no-reply@aomaro.com")
  layout "mailer"
end
