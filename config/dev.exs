import Config

# ВАЖНО: Проверьте, что переменные PG_USER, PG_PASS, PG_DB существуют в .env!
config :music_platform_api, MusicPlatformApi.Repo,
  username: System.get_env("PG_USER"),
  password: System.get_env("PG_PASS"),
  hostname: "localhost",
  database: System.get_env("PG_DB"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :music_platform_api, MusicPlatformApiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "4TTNLglEV0SDXh7K+lMnq3XmK8nzjj4fiFqcvQe78TmLPiTNsmn9XoNTjmU2rToW",
  watchers: []

config :music_platform_api, dev_routes: true
config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :swoosh, :api_client, false
