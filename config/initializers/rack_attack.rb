require "uri"

# Protect the public recipe endpoint from abuse and runaway API cost. Rules are
# scoped to POST /chats so the rest of the app (including /up) stays untouched.
Rack::Attack.enabled = ENV.fetch("RACK_ATTACK_ENABLED", "true") == "true"

# Throttle counters live in a dedicated Redis database in production. In
# development and test a process-local store is enough. RedisCacheStore already
# fails open on connection errors; the handler just makes the degradation loud.
Rack::Attack.cache.store = if Rails.env.production? && ENV["REDIS_URL"].present?
  throttle_url = URI.parse(ENV["REDIS_URL"])
  throttle_url.path = "/1" if %w[redis rediss].include?(throttle_url.scheme)

  ActiveSupport::Cache::RedisCacheStore.new(
    url: throttle_url.to_s,
    namespace: "recipe-helper:throttle",
    connect_timeout: 1,
    read_timeout: 1,
    write_timeout: 1,
    error_handler: lambda do |method:, exception:, returning:|
      Rails.logger.warn("[rack-attack] cache #{method} failed " \
                        "(#{exception.class}: #{exception.message}); failing open")
      returning
    end
  )
else
  ActiveSupport::Cache::MemoryStore.new
end

positive_int = lambda do |name, default|
  value = Integer(ENV.fetch(name, default.to_s))
  value.positive? ? value : default
rescue ArgumentError, TypeError
  default
end

ip_limit = positive_int.call("CHAT_IP_LIMIT", 10)
ip_period = positive_int.call("CHAT_IP_PERIOD", 1.hour.to_i)
global_limit = positive_int.call("CHAT_GLOBAL_LIMIT", 100)
global_period = positive_int.call("CHAT_GLOBAL_PERIOD", 1.hour.to_i)
recipe_request = ->(request) { request.post? && request.path == "/chats" }

Rack::Attack.throttle("recipes per ip", limit: ip_limit, period: ip_period) do |request|
  request.ip if recipe_request.call(request)
end

Rack::Attack.throttle("recipes globally", limit: global_limit, period: global_period) do |request|
  "all" if recipe_request.call(request)
end

# A custom responder is needed because Rack::Attack's automatic Retry-After
# header is only added to its default plain-text responder.
Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"] || {}
  now = (match_data[:epoch_time] || Time.now.to_i).to_i
  period = (match_data[:period] || ip_period).to_i
  retry_after = [ period - (now % period), 1 ].max
  wait = "#{retry_after} second#{"s" unless retry_after == 1}"

  body = <<~HTML
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Too many recipe requests</title>
        <style>
          body { margin: 0; min-height: 100vh; display: grid; place-items: center;
                 background: #faf6ef; color: #3d2b1f; font-family: system-ui, sans-serif; }
          main { max-width: 32rem; margin: 2rem; padding: 2rem; border-radius: 1rem;
                 background: #fffdf8; border: 1px solid #e3d5c4;
                 box-shadow: 0 12px 32px rgba(61, 43, 31, 0.08); }
          h1 { margin-top: 0; font-size: 1.5rem; }
          a { color: #a4472e; font-weight: 600; }
        </style>
      </head>
      <body>
        <main>
          <h1>Too many recipe requests</h1>
          <p>We're giving the kitchen a breather. Please wait about #{wait} before asking for more recipes.</p>
          <p><a href="/">Back to Recipe Helper</a></p>
        </main>
      </body>
    </html>
  HTML

  [
    429,
    {
      "content-type" => "text/html; charset=utf-8",
      "retry-after" => retry_after.to_s,
      "cache-control" => "no-store"
    },
    [ body ]
  ]
end

ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  request = payload[:request]
  Rails.logger.info(
    "[rack-attack] throttled #{request.env["rack.attack.matched"]} " \
    "(#{request.env["rack.attack.match_type"]}) for #{request.ip}"
  )
end
