defmodule MusicPlatformApiWeb.Router do
  use MusicPlatformApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MusicPlatformApiWeb do
    pipe_through :api

    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/logout", AuthController, :logout
    get "/profile/:id", AuthController, :get_public_profile
    get "/profile", AuthController, :get_profile

    put "/change-password", AuthController, :change_password

    post "/reset-password/request", AuthController, :request_reset_password
    post "/reset-password/confirm", AuthController, :confirm_reset_password

    put "/update-nickname", AuthController, :update_nickname
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:music_platform_api, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: MusicPlatformApiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
