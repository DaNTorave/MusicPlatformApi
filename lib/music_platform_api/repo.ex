defmodule MusicPlatformApi.Repo do
  use Ecto.Repo,
    otp_app: :music_platform_api,
    adapter: Ecto.Adapters.Postgres
end
