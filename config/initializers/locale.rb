Rails.application.config.after_initialize do
  I18n.exception_handler = ->(exception, _options) do
    case exception
    when I18n::MissingTranslation
      exception.message
    else
      raise exception
    end
  end
end
