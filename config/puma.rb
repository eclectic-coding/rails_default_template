max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
workers Integer(ENV["WEB_CONCURRENCY"] || 2)
threads min_threads_count, max_threads_count

rails_env = ENV.fetch("RAILS_ENV") { "development" }
rails_port = ENV.fetch("PORT") { 3000 }
environment rails_env
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }
worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"

if rails_env == "development"
  worker_timeout 3600
  ssl_bind(
    "0.0.0.0",
    rails_port,
    key: ENV.fetch("SSL_KEY_FILE", "config/certs/localhost-key.pem"),
    cert: ENV.fetch("SSL_CERT_FILE", "config/certs/localhost.pem"),
    verify_mode: "none"
  )
else
  port rails_port
end

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

preload_app!
