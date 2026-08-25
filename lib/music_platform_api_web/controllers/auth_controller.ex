defmodule MusicPlatformApiWeb.AuthController do
  use MusicPlatformApiWeb, :controller
  alias MusicPlatformApi.{Auth, PasswordUtils}
  alias MusicPlatformApi.User
  alias MusicPlatformApi.Auth

  defp authenticate_request(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) <- Auth.get_user_from_token(token) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Требуется авторизация"})
        |> halt()
    end
  end

  def register(conn, params) do
    case Auth.register_user(params) do
      {:ok, %User{} = user, token} when is_binary(token) ->
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
          },
          token: token
        })

      {:ok, %User{} = user} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          message: "Регистрация прошла успешно, но без токена",
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
          {:ok, token} when is_binary(token) ->
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

  def change_password(conn, %{
        "current_password" => cur_pwd,
        "new_password" => new_pwd,
        "new_password_confirmation" => new_pwd_conf
      }) do
    conn = authenticate_request(conn, [])
    if conn.halted do
      conn
    else
      user = conn.assigns.current_user

      case Auth.change_password(user, cur_pwd, new_pwd, new_pwd_conf) do
        {:ok, _user} ->
          json(conn, %{message: "Пароль успешно изменен"})

        {:error, :invalid_current_password} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Неверный текущий пароль"})

        {:error, :password_mismatch} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Новые пароли не совпадают"})

        {:error, :password_confirmation_mismatch} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Новые пароли не совпадают"})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Ошибка валидации пароля", details: inspect(changeset.errors)})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: to_string(reason)})
      end
    end
  end

  def request_reset_password(conn, %{"email" => email}) do
    case Auth.request_password_reset(email) do
      {:ok, %{code: code, reset_token: reset_token}} ->
        # На выход отдается сгенерированный код и токен подтверждения
        json(conn, %{
          message: "Код подтверждения сгенерирован",
          code: code,
          reset_token: reset_token
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Пользователь с такой почтой не найден"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: to_string(reason)})
    end
  end

  def confirm_reset_password(conn, %{
        "reset_token" => reset_token,
        "code" => code,
        "new_password" => new_pwd,
        "new_password_confirmation" => new_pwd_conf
      }) do
    case Auth.reset_password(reset_token, code, new_pwd, new_pwd_conf) do
      {:ok, _user} ->
        json(conn, %{message: "Пароль успешно обновлен"})

      {:error, :password_confirmation_mismatch} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Пароли не совпадают"})

      {:error, :invalid_code} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Неверный код подтверждения"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Не удалось сбросить пароль: #{inspect(reason)}"})
    end
  end

  def get_profile(conn, _params) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        IO.inspect(token, label: "Token received")

        case Auth.verify_token(token) do
          {:ok, claims} ->
            IO.inspect(claims, label: "Claims from token")

            case claims do
              %{"user_id" => user_id} when is_integer(user_id) ->
                case Auth.get_user(user_id) do
                  nil ->
                    return_error(conn, :not_found, "Пользователь не найден")
                  user ->
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
                end
              _ ->
                return_error(conn, :unauthorized, "Недействительный токен (нет user_id)")
            end
          {:error, reason} ->
            IO.inspect(reason, label: "Token verification error")
            return_error(conn, :unauthorized, "Недействительный токен: #{reason}")
        end
      _ ->
        return_error(conn, :unauthorized, "Отсутствует токен авторизации")
    end
  end

  def get_public_profile(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {user_id, ""} ->
        case Auth.get_user(user_id) do
          nil ->
            return_error(conn, :not_found, "Пользователь не найден")
          user ->
            case get_req_header(conn, "authorization") do
              ["Bearer " <> token] ->
                case Auth.verify_token(token) do
                  {:ok, claims} ->
                    current_user_id = claims["user_id"]
                    if is_integer(current_user_id) && user.id == current_user_id do
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
      _ ->
        return_error(conn, :bad_request, "Неверный формат ID пользователя")
    end
  end

  def update_nickname(conn, %{"nickname" => nickname}) do
    conn = authenticate_request(conn, [])

    if conn.halted do
      conn
    else
      user = conn.assigns.current_user

      case Auth.update_nickname(user, nickname) do
        {:ok, updated_user} ->
          case Auth.generate_token(updated_user) do
            {:ok, new_token} ->
              json(conn, %{
                message: "Никнейм успешно обновлен",
                token: new_token,
                user: %{
                  id: updated_user.id,
                  login: updated_user.login,
                  nickname: updated_user.nickname,
                  email: updated_user.email
                }
              })

            {:error, reason} ->
              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Ошибка генерации токена: #{reason}"})
          end

        {:error, reason} when is_binary(reason) ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: reason})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Ошибка валидации", details: inspect(changeset.errors)})

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: inspect(reason)})
      end
    end
  end

  def update_nickname(conn, _params) do
    return_error(conn, :bad_request, "Требуется ник")
  end

  def change_password(conn, %{"current_password" => current, "new_password" => new}) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case Auth.verify_token(token) do
          {:ok, claims} ->
            case claims do
              %{"user_id" => user_id} when is_integer(user_id) ->
                case Auth.get_user(user_id) do
                  nil ->
                    return_error(conn, :not_found, "Пользователь не найден")
                  user ->
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
                end
              _ ->
                return_error(conn, :unauthorized, "Недействительный токен")
            end
          {:error, _} ->
            return_error(conn, :unauthorized, "Недействительный токен")
        end
      _ ->
        return_error(conn, :unauthorized, "Отсутствует токен авторизации")
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
