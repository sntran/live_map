import Config

config :phoenix, :json_library, Jason

if Mix.env == :dev do
  config :mix_test_watch,
    clear: true
end
