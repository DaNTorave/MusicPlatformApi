defmodule MusicPlatformApiWeb.AuthController do
  use MusicPlatformApiWeb, :controller
  alias MusicPlatformApi.{Auth, PasswordUtils}
  alias MusicPlatformApi.User

  def register(conn, params) do
    case Auth.register_user(params) do
      {:ok, %User{} = user} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          message: "Регистрация прошла успешно",
          user: %{
            id: user.id,
            login: user.login,
            email: user.email,
            nickname: user.nickname,
            role: user.role,
            is_premium: user.is_premium,
            avatar: user.avatar,
            inserted_at: user.inserted_at,
            updated_at: user.updated_at
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, errors: format_errors(changeset)})
    end
  end

  def login(conn, %{"login" => login, "password" => password}) do
    case Auth.authenticate(login, password) do
      {:ok, user} ->
        case Auth.generate_token(user) do
          token when is_binary(token) ->
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              message: "Вход выполнен успешно",
              user: %{
                id: user.id,
                login: user.login,
                email: user.email,
                nickname: user.nickname,
                role: user.role,
                is_premium: user.is_premium,
                avatar: user.avatar,
                inserted_at: user.inserted_at,
                updated_at: user.updated_at
              },
              token: token
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{success: false, error: "Ошибка генерации токена: #{reason}"})
        end

      {:error, message} ->
        Process.sleep(1000)
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: message})
    end
  end

  def login(conn, _params) do
    return_error(conn, :bad_request, "Требуется логин и пароль")
  end

  def logout(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{success: true, message: "Выход выполнен успешно"})
  end

  def get_profile(conn, _params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Auth.verify_token(token),
         user when not is_nil(user) <- Auth.get_user(claims["user_id"]) do

      conn
      |> put_status(:ok)
      |> json(%{
        success: true,
        user: %{
          id: user.id,
          login: user.login,
          email: user.email,
          nickname: user.nickname,
          role: user.role,
          is_premium: user.is_premium,
          avatar: user.avatar,
          inserted_at: user.inserted_at,
          updated_at: user.updated_at
        }
      })
    else
      [] -> return_error(conn, :unauthorized, "Отсутствует токен авторизации")
      {:error, _} -> return_error(conn, :unauthorized, "Недействительный токен")
      nil -> return_error(conn, :not_found, "Пользователь не найден")
      _ -> return_error(conn, :unauthorized, "Недействительный или отсутствующий токен")
    end
  end

  def get_public_profile(conn, %{"id" => id}) do
    case Auth.get_user(String.to_integer(id)) do
      nil ->
        return_error(conn, :not_found, "Пользователь не найден")

      user ->
        case get_req_header(conn, "authorization") do
          ["Bearer " <> token] ->
            case Auth.verify_token(token) do
              {:ok, claims} ->
                current_user_id = claims["user_id"]
                if user.id == current_user_id do
                  conn
                  |> put_status(:ok)
                  |> json(%{
                    success: true,
                    profile: %{
                      id: user.id,
                      login: user.login,
                      email: user.email,
                      nickname: user.nickname,
                      role: user.role,
                      is_premium: user.is_premium,
                      avatar: user.avatar,
                      inserted_at: user.inserted_at,
                      updated_at: user.updated_at
                    }
                  })
                else
                  conn
                  |> put_status(:ok)
                  |> json(%{
                    success: true,
                    profile: %{
                      id: user.id,
                      login: user.login,
                      nickname: user.nickname,
                      avatar: user.avatar,
                      role: user.role,
                      is_premium: user.is_premium,
                      inserted_at: user.inserted_at
                    }
                  })
                end
              {:error, _} ->
                conn
                |> put_status(:ok)
                |> json(%{
                  success: true,
                  profile: %{
                    id: user.id,
                    login: user.login,
                    nickname: user.nickname,
                    avatar: user.avatar,
                    role: user.role,
                    is_premium: user.is_premium,
                    inserted_at: user.inserted_at
                  }
                })
            end
          _ ->
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              profile: %{
                id: user.id,
                login: user.login,
                nickname: user.nickname,
                avatar: user.avatar,
                role: user.role,
                is_premium: user.is_premium,
                inserted_at: user.inserted_at
              }
            })
        end
    end
  end

  def update_nickname(conn, %{"nickname" => new_nickname}) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Auth.verify_token(token),
         user when not is_nil(user) <- Auth.get_user(claims["user_id"]) do

      case Auth.update_nickname(user, new_nickname) do
        {:ok, updated_user} ->
          conn
          |> put_status(:ok)
          |> json(%{
            success: true,
            message: "Ник успешно обновлен",
            user: %{
              id: updated_user.id,
              login: updated_user.login,
              email: updated_user.email,
              nickname: updated_user.nickname,
              role: updated_user.role,
              is_premium: updated_user.is_premium,
              avatar: updated_user.avatar
            }
          })

        {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
          conn
          |> put_status(:bad_request)
          |> json(%{success: false, errors: format_errors(changeset)})

        {:error, message} when is_binary(message) ->
          return_error(conn, :bad_request, message)
      end
    else
      [] -> return_error(conn, :unauthorized, "Отсутствует токен авторизации")
      {:error, _} -> return_error(conn, :unauthorized, "Недействительный токен")
      nil -> return_error(conn, :not_found, "Пользователь не найден")
      _ -> return_error(conn, :unauthorized, "Недействительный или отсутствующий токен")
    end
  end

  def update_nickname(conn, _params) do
    return_error(conn, :bad_request, "Требуется ник")
  end

  def change_password(conn, %{"current_password" => current, "new_password" => new}) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Auth.verify_token(token),
         user when not is_nil(user) <- Auth.get_user(claims["user_id"]) do

      if Auth.check_password(user, current) do
        case Auth.update_password(user, new) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{success: true, message: "Пароль успешно обновлен"})

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{success: false, errors: format_errors(changeset)})
        end
      else
        return_error(conn, :unauthorized, "Текущий пароль неверен")
      end
    else
      [] -> return_error(conn, :unauthorized, "Отсутствует токен авторизации")
      {:error, _} -> return_error(conn, :unauthorized, "Недействительный токен")
      nil -> return_error(conn, :not_found, "Пользователь не найден")
      _ -> return_error(conn, :unauthorized, "Недействительный или отсутствующий токен")
    end
  end

  def change_password(conn, _params) do
    return_error(conn, :bad_request, "Требуется текущий и новый пароль")
  end

  def reset_password(conn, %{"email" => email}) do
    case Auth.get_user_by_email(email) do
      nil ->
        return_error(conn, :not_found, "Пользователь с таким email не найден")

      user ->
        new_password = PasswordUtils.generate_temporary_password()

        case Auth.update_password(user, new_password) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              message: "Пароль сброшен успешно. Новый пароль отправлен на ваш email",
              temporary_password: new_password
            })

          {:error, _} ->
            return_error(conn, :internal_server_error, "Не удалось сбросить пароль")
        end
    end
  end

  def reset_password(conn, _params) do
    return_error(conn, :bad_request, "Требуется email")
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> translate_validation_errors()
  end

  defp translate_validation_errors(errors) do
    Map.new(errors, fn {field, messages} ->
      translated = Enum.map(messages, fn msg ->
        case msg do
          "can't be blank" -> "не может быть пустым"
          "has already been taken" -> "уже занят"
          "is invalid" -> "неверный формат"
          "has invalid format" -> "неверный формат"
          "should be at least %{count} character(s)" -> "должен содержать минимум %{count} символов"
          "should be at most %{count} character(s)" -> "должен содержать максимум %{count} символов"
          "should be at least %{count} item(s)" -> "должен содержать минимум %{count} элементов"
          "should be at most %{count} item(s)" -> "должен содержать максимум %{count} элементов"
          "must be accepted" -> "должно быть принято"
          "is reserved" -> "зарезервировано"
          "does not match confirmation" -> "не совпадает с подтверждением"
          "is still associated with this entry" -> "все еще связано с этой записью"
          "are still associated with this entry" -> "все еще связаны с этой записью"
          "invalid email format" -> "неверный формат email"
          "role must be 'member'" -> "роль должна быть 'member'"
          _ -> msg
        end
      end)
      {field, translated}
    end)
  end

  defp return_error(conn, status, error_message) do
    conn
    |> put_status(status)
    |> json(%{success: false, error: error_message})
  end

  def options(conn, _params) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
    |> put_resp_header("access-control-allow-headers", "accept, authorization, content-type")
    |> put_resp_header("access-control-max-age", "600")
    |> send_resp(:no_content, "")
  end
end
