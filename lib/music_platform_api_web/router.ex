defmodule MusicPlatformApiWeb.Router do
  use MusicPlatformApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MusicPlatformApiWeb do
    pipe_through :api

    # Пользователь
    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/logout", AuthController, :logout
    get "/profile/:id", AuthController, :get_public_profile
    get "/profile", AuthController, :get_profile

    post "/profile/avatar", AuthController, :upload_avatar

    put "/change-password", AuthController, :change_password

    post "/reset-password/request", AuthController, :request_reset_password
    post "/reset-password/confirm", AuthController, :confirm_reset_password

    put "/update-nickname", AuthController, :update_nickname

    # Аудиопоток и скачивание
    get "/stream/:id", StreamController, :stream
    get "/download/:id", StreamController, :download

    # Каталог и уведомления
    get "/artists", MusicController, :list_artists
    get "/artists/:id", MusicController, :get_artist
    get "/notifications", NotificationController, :index
    put "/notifications/:id/read", NotificationController, :mark_read

    get "/charts/tracks", MusicController, :top_tracks
    get "/charts/artists", MusicController, :top_artists

    post "/upload/artist", MusicController, :create_artist
    post "/upload/album", MusicController, :create_album
    post "/upload/single", MusicController, :create_single

    get "/tracks/:id", MusicController, :get_track

    put "/tracks/:id", MusicController, :update_track
    put "/artists/:id", MusicController, :update_artist

    delete "/tracks/:id", MusicController, :delete_track
    delete "/albums/:id", MusicController, :delete_album
    delete "/artists/:id", MusicController, :delete_artist

    get "/moderation/pending", ModerationController, :pending_list
    post "/moderation/decision", ModerationController, :make_decision
    post "/moderation/approve-with-edit", ModerationController, :approve_with_edit

    # Управление ролями (только для owner)
    get "/admin/users", AdminController, :list_users
    put "/admin/users/:id/role", AdminController, :update_role

    # Избранное
    get "/favorites", MusicController, :list_favorites
    get "/favorites/ids", MusicController, :favorite_ids
    post "/favorites/toggle", MusicController, :toggle_favorite

    # Плейлисты
    get "/playlists", MusicController, :list_my_playlists
    get "/users/:id/playlists", MusicController, :list_user_playlists
    get "/playlists/:id", MusicController, :get_playlist
    post "/playlists", MusicController, :create_playlist
    post "/playlists/:id/update", MusicController, :update_playlist
    put "/playlists/:id", MusicController, :update_playlist
    delete "/playlists/:id", MusicController, :delete_playlist
    post "/playlists/:id/tracks", MusicController, :toggle_playlist_track
    delete "/playlists/:id/tracks/:track_id", MusicController, :remove_playlist_track
  end

  if Application.compile_env(:music_platform_api, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: MusicPlatformApiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
