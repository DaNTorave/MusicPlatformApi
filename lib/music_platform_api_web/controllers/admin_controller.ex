defmodule MusicPlatformApiWeb.AdminController do
  use MusicPlatformApiWeb, :controller
  alias MusicPlatformApi.{Auth, User}

  # Проверка авторизации и наличия прав администратора или владельца
  defp require_admin_or_owner(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) <- Auth.get_user_from_token(token) do
      if user.role in ["owner", "admin"] do
        assign(conn, :current_user, user)
      else
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Доступ запрещен. Требуются права администратора или владельца."})
        |> halt()
      end
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Требуется авторизация"})
        |> halt()
    end
  end

  # Получение списка пользователей и доступных для назначения ролей
  def list_users(conn, params) do
    conn = require_admin_or_owner(conn, [])
    if conn.halted do
      conn
    else
      current_user = conn.assigns.current_user
      search = Map.get(params, "query", "")
      users = Auth.list_users(search)

      # Формирование списка ролей в зависимости от прав вызывающего пользователя
      available_roles =
        if current_user.role == "owner" do
          User.roles()
        else
          ["member", "moderator"]
        end

      formatted_users =
        Enum.map(users, fn u ->
          %{
            id: u.id,
            login: u.login,
            email: u.email,
            nickname: u.nickname,
            avatar: u.avatar,
            role: u.role,
            is_premium: u.is_premium,
            inserted_at: u.inserted_at
          }
        end)

      json(conn, %{
        success: true,
        users: formatted_users,
        roles: available_roles,
        current_user_role: current_user.role
      })
    end
  end

  # Назначение роли пользователю с проверкой иерархии прав
  def update_role(conn, %{"id" => user_id, "role" => new_role}) do
    conn = require_admin_or_owner(conn, [])
    if conn.halted do
      conn
    else
      current_user = conn.assigns.current_user

      case Auth.get_user(user_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Пользователь не найден"})

        target_user ->
          # Проверка ограничений по иерархии ролей
          cond do
            # Запрет понижения роли владельца самому себе
            to_string(current_user.id) == to_string(target_user.id) and current_user.role == "owner" and new_role != "owner" ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Нельзя понизить собственную роль владельца"})

            # Администратор не может изменять роли пользователей owner и admin
            current_user.role == "admin" and target_user.role in ["owner", "admin"] ->
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Администратор не может изменять роли владельцев и других администраторов"})

            # Администратор может назначать только роли moderator и member
            current_user.role == "admin" and new_role not in ["moderator", "member"] ->
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Администратор может назначать только роли модератора или пользователя"})

            # Выполнение смены роли
            true ->
              case Auth.change_user_role(target_user, new_role) do
                {:ok, updated} ->
                  json(conn, %{
                    success: true,
                    message: "Роль успешно изменена",
                    user: %{
                      id: updated.id,
                      login: updated.login,
                      nickname: updated.nickname,
                      role: updated.role
                    }
                  })

                {:error, %Ecto.Changeset{} = changeset} ->
                  errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
                  conn
                  |> put_status(:bad_request)
                  |> json(%{error: "Ошибка валидации роли", details: errors})
              end
          end
      end
    end
  end

  def update_role(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Необходимо передать id и role"})
  end
end
