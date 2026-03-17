if ENV["PREFLIGHT_IDLE_SHUTDOWN"].present?
  require_relative "../../app/middleware/idle_shutdown"
  Rails.application.config.middleware.use IdleShutdown
end
