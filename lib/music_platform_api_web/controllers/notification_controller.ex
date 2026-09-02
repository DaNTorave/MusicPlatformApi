defmodule MusicPlatformApiWeb.NotificationController do
  use MusicPlatformApiWeb, :controller
  import Ecto.Query
  alias MusicPlatformApi.{Auth, Repo}
  alias MusicPlatformApi.Notifications.Notification

  def index(conn, _params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) <- Auth.get_user_from_token(token) do
      notifications =
        Repo.all(from n in Notification, where: n.user_id == ^user.id, order_by: [desc: n.inserted_at])

      json(conn, %{notifications: notifications})
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "Требуется авторизация"})
    end
  end

  def mark_read(conn, %{"id" => id}) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) <- Auth.get_user_from_token(token),
         notification when not is_nil(notification) <- Repo.get_by(Notification, id: id, user_id: user.id) do
      {:ok, updated} =
        notification
        |> Ecto.Changeset.change(%{is_read: true})
        |> Repo.update()

      json(conn, %{success: true, notification: updated})
    else
      _ -> conn |> put_status(:bad_request) |> json(%{error: "Ошибка изменения статуса"})
    end
  end
end
