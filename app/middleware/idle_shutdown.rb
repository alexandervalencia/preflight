class IdleShutdown
  @mutex = Mutex.new
  @last_request_at = Time.now

  def initialize(app)
    @app = app
  end

  def call(env)
    self.class.touch
    @app.call(env)
  end

  def self.touch
    @mutex.synchronize { @last_request_at = Time.now }
  end

  def self.last_request_at
    @mutex.synchronize { @last_request_at }
  end
end
