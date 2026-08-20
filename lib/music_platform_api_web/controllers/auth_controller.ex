defmodule MusicPlatformApiWeb.AuthController do
  use MusicPlatformApiWeb, :controller
  alias MusicPlatformApi.{Auth, PasswordUtils}
  alias MusicPlatformApi.User

  def register(conn, params) do
    # Проверка наличия пароля
    password = params["password"] || params[:password]

    if is_nil(password) or not PasswordUtils.strong_password?(password) do
      return_error(conn, :bad_request, "Password is required and must be strong enough")
    else
      case Auth.register_user(params) do
        {:ok, %User{} = user} ->
          # Не возвращаем пароль и хеш
          user_map =
            user
            |> Map.from_struct()
            |> Map.drop([:password, :password_hash])

          conn
          |> put_status(:created)
          |> json(%{success: true, user: user_map})

        {:error, changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{success: false, errors: format_errors(changeset)})
      end
    end
  end

  def login(conn, %{"login" => login, "password" => password}) do
    case Auth.authenticate(login, password) do
      {:ok, user} ->
        case Auth.generate_token(user) do
          token when is_binary(token) ->
            user_map =
              user
              |> Map.from_struct()
              |> Map.drop([:password, :password_hash])

            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              user: user_map,
              token: token
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{success: false, error: "Failed to generate token: #{reason}"})
        end

      {:error, message} ->
        # Защита от брутфорса - задержка
        Process.sleep(1000)
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: message})
    end
  end

  def login(conn, _params) do
    return_error(conn, :bad_request, "Login and password are required")
  end

  def logout(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{success: true, message: "Logged out successfully"})
  end

  def get_profile(conn, _params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Auth.verify_token(token),
         user when not is_nil(user) <- Auth.get_user(claims["user_id"]) do

      user_map =
        user
        |> Map.from_struct()
        |> Map.drop([:password, :password_hash])

      conn
      |> put_status(:ok)
      |> json(%{success: true, user: user_map})
    else
      [] ->
        return_error(conn, :unauthorized, "Missing authorization token")

      {:error, _} ->
        return_error(conn, :unauthorized, "Invalid token")

      nil ->
        return_error(conn, :not_found, "User not found")

      _ ->
        return_error(conn, :unauthorized, "Invalid or missing token")
    end
  end

  # Изменение пароля
  def change_password(conn, %{"current_password" => current, "new_password" => new}) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Auth.verify_token(token),
         user when not is_nil(user) <- Auth.get_user(claims["user_id"]) do

      if Auth.check_password(user, current) do
        if PasswordUtils.strong_password?(new) do
          case Auth.update_password(user, new) do
            {:ok, _} ->
              conn
              |> put_status(:ok)
              |> json(%{success: true, message: "Password updated successfully"})

            {:error, changeset} ->
              conn
              |> put_status(:bad_request)
              |> json(%{success: false, errors: format_errors(changeset)})
          end
        else
          return_error(conn, :bad_request, "New password is not strong enough")
        end
      else
        return_error(conn, :unauthorized, "Current password is incorrect")
      end
    else
      [] ->
        return_error(conn, :unauthorized, "Missing authorization token")

      {:error, _} ->
        return_error(conn, :unauthorized, "Invalid token")

      nil ->
        return_error(conn, :not_found, "User not found")

      _ ->
        return_error(conn, :unauthorized, "Invalid or missing token")
    end
  end

  def change_password(conn, _params) do
    return_error(conn, :bad_request, "Current password and new password are required")
  end

  # Сброс пароля (генерация нового)
  def reset_password(conn, %{"email" => email}) do
    case Auth.get_user_by_email(email) do
      nil ->
        return_error(conn, :not_found, "User not found")

      user ->
        new_password = PasswordUtils.generate_temporary_password()

        case Auth.update_password(user, new_password) do
          {:ok, _} ->
            # В реальном приложении здесь отправка email с новым паролем
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              message: "Password reset successfully",
              temporary_password: new_password  # Только для демонстрации
            })

          {:error, _} ->
            return_error(conn, :internal_server_error, "Failed to reset password")
        end
    end
  end

  def reset_password(conn, _params) do
    return_error(conn, :bad_request, "Email is required")
  end

  # Вспомогательные функции
  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp return_error(conn, status, error_message) do
    conn
    |> put_status(status)
    |> json(%{success: false, error: error_message})
  end
end
