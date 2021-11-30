import Config

config :phoenix, :json_library, Jason

if Mix.env == :dev do
  config :mix_test_watch,
    clear: true
end

if Mix.env() == :test do
  # We don't run a server during test. If one is required,
  # you can enable the server option below.
  config :live_map, LiveMapTestApp.Endpoint,
    secret_key_base: "DC7N7zO/AVr5qqVk+ZRAm1PM4arGnoZ7847JlrRmUknGCbFIdcL14+wF9Ws085mU",
    live_view: [signing_salt: "NsyigQtD"]

  # Print only warnings and errors during test
  config :logger, level: :warn
end
