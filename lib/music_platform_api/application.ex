defmodule MusicPlatformApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MusicPlatformApiWeb.Telemetry,
      MusicPlatformApi.Repo,
      {DNSCluster, query: Application.get_env(:music_platform_api, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MusicPlatformApi.PubSub},
      # Start a worker by calling: MusicPlatformApi.Worker.start_link(arg)
      # {MusicPlatformApi.Worker, arg},
      # Start to serve requests, typically the last entry
      MusicPlatformApiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MusicPlatformApi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MusicPlatformApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
