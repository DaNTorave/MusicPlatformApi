import Config

config :music_platform_api,
  ecto_repos: [MusicPlatformApi.Repo],
  generators: [timestamp_type: :utc_datetime]

config :music_platform_api, MusicPlatformApiWeb.Endpoint,
  url: [host: "localhost", port: 4000],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: MusicPlatformApiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MusicPlatformApi.PubSub,
  live_view: [signing_salt: "vO8eXeeY"]

config :music_platform_api, MusicPlatformApi.Mailer, adapter: Swoosh.Adapters.Local

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

if config_env() in [:dev, :test] do
  import_config ".env.exs"
end

import_config "#{config_env()}.exs"
