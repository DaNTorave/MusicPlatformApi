defmodule MusicPlatformApiWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :music_platform_api

  @session_options [
    store: :cookie,
    key: "_music_platform_api_key",
    signing_salt: "YxTbIRdI",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Corsica,
    origins: [
      "http://localhost:3000",
      "http://localhost:5173",
      "http://localhost:8080"
    ],
    allow_credentials: true,
    max_age: 600,
    headers: [
      "accept",
      "authorization",
      "content-type",
      "x-requested-with",
      "x-csrf-token",
      "x-api-key",
      "cache-control",
      "if-match",
      "if-modified-since",
      "if-none-match",
      "if-unmodified-since"
    ],
    expose: [
      "x-request-id",
      "x-total-count",
      "x-next-page",
      "x-prev-page"
    ],
    methods: [
      "GET",
      "POST",
      "PUT",
      "DELETE",
      "OPTIONS",
      "PATCH",
      "HEAD"
    ]

  plug Plug.Static,
    at: "/",
    from: :music_platform_api,
    gzip: not code_reloading?,
    only: MusicPlatformApiWeb.static_paths()

  plug Plug.Static,
    at: "/uploads",
    from: Path.expand("priv/static/uploads"),
    gzip: false

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :music_platform_api
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 250_000_000

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug MusicPlatformApiWeb.Router
end
