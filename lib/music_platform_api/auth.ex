defmodule MusicPlatformApi.Auth do
  alias MusicPlatformApi.{Repo, User, Token}
  import Ecto.Query

  # Генерация ников
  defp generate_random_nickname do
    adjectives = ["cool", "happy", "brave", "smart", "lucky", "wild", "free", "bold", "calm", "swift"]
    nouns = ["panda", "tiger", "eagle", "wolf", "fox", "bear", "lion", "hawk", "dove", "whale"]
    number = Enum.random(1000..9999)

    adjective = Enum.random(adjectives)
    noun = Enum.random(nouns)

    "#{adjective}_#{noun}_#{number}"
  end

  # Поиск по логину или почте
  defp get_user_by_login_or_email(login_or_email) do
    query = from u in User,
            where: u.login == ^login_or_email or u.email == ^login_or_email,
            limit: 1

    Repo.one(query)
  end

  # Регистрация
  def register_user(attrs) do
    # Если ник пустой - вызывает генерацию
    nickname = Map.get(attrs, "nickname")
    attrs =
      if is_nil(nickname) || String.trim(nickname) == "" do
        Map.put(attrs, "nickname", generate_random_nickname())
      else
        attrs
      end

    # Перекидывает в user.ex для валидации и хеширования пароля и пытается сделать INSERT в БД
    case %User{}
      |> User.registration_changeset(attrs)
      |> Repo.insert() do
      {:ok, user} ->
        loaded_user =
          # Если айдишник не пришёл с Repo.insert, то получение айди через логин
          if is_nil(user.id) do
            case Repo.get_by(User, login: user.login) do
              nil -> user
              found_user -> found_user
            end
          else
            user
          end

        # Ответ уникальным сгенерированным токеном
        case MusicPlatformApi.Auth.generate_token(loaded_user) do
          {:ok, token} ->
            {:ok, loaded_user, token}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Аунтетификация по логину или паролю
  def authenticate(login_or_email, password) do
    user = get_user_by_login_or_email(login_or_email)

    case user do
      nil -> {:error, "Неверный логин или пароль"}
      user ->
        if User.valid_password?(user, password) do
          {:ok, user}
        else
          {:error, "Неверный логин или пароль"}
        end
    end
  end

  # Генерация 90 дневного токена
  def generate_token(user) do
    user_id = user.id

    if is_nil(user_id) do
      {:error, "User ID is nil"}
    else
      claims = %{
        "user_id" => user_id,
        "login" => user.login,
        "email" => user.email,
        "nickname" => user.nickname || "",
        "exp" => System.system_time(:second) + 86400 * 90
      }

      IO.inspect(claims, label: "Claims being generated")

      case Token.generate_token(claims) do
        {:ok, token, _claims} ->
          {:ok, token}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Проверка токена на валидность и срок действия
  def verify_token(token) do
    case Token.verify_token(token) do
      {:ok, claims} ->
        IO.inspect(claims, label: "Verified claims")
        {:ok, claims}
      {:error, reason} -> {:error, "Недействительный токен: #{reason}"}
    end
  end

  # Извлечение юзера из бд по токену
  def get_user_from_token(token) do
    case verify_token(token) do
      {:ok, claims} ->
        case claims do
          # Если айдишник числовой
          %{"user_id" => user_id} when is_integer(user_id) ->
            Repo.get(User, user_id)

          # Если айдишник строкой
          %{"user_id" => user_id} when is_binary(user_id) ->
            case Integer.parse(user_id) do
              {int_id, ""} -> Repo.get(User, int_id)
              _ -> nil
            end
          _ ->
            nil
        end
      {:error, _} -> nil
    end
  end

  # Получение юзера из числового айдишника
  def get_user(id) when is_integer(id) do
    Repo.get(User, id)
  end

  # Получение из строкового
  def get_user(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> Repo.get(User, int_id)
      _ -> nil
    end
  end

  # Fallback для невалидных
  def get_user(_), do: nil

  # Получения юзера по логину, почте, нику
  def get_user_by_login(login) do
    Repo.get_by(User, login: login)
  end

  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_nickname(nickname) do
    Repo.get_by(User, nickname: nickname)
  end

  # Обновление разрешённых атрибутов пользователя
  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  # Хеширование и обновление пароля в БД
  def update_password(%User{} = user, new_password) do
    changeset =
      user
      |> Ecto.Changeset.cast(%{password: new_password}, [:password])
      |> User.put_password_hash()

    Repo.update(changeset)
  end

  # Обновление никнейма с валидациями
  def update_nickname(user, new_nickname) do
    new_nickname = String.trim(new_nickname)

    if new_nickname == "" do
      {:error, "Ник не может быть пустым"}
    else
      existing_user = get_user_by_nickname(new_nickname)

      cond do
        existing_user && existing_user.id != user.id ->
          {:error, "Ник уже занят"}
        true ->
          user
          |> Ecto.Changeset.cast(%{nickname: new_nickname}, [:nickname])
          |> Ecto.Changeset.validate_length(:nickname, min: 1, max: 50)
          |> Repo.update()
      end
    end
  end


  def check_password(user, password) do
    User.valid_password?(user, password)
  end

  # Смена пароля с подтверждением старого
  def change_password(%User{} = user, current_password, new_password, new_password_confirmation) do
    cond do
      !User.valid_password?(user, current_password) -> {:error, :invalid_current_password}
      new_password != new_password_confirmation -> {:error, :password_mismatch}
      true -> update_password(user, new_password)
    end
  end

  # Запрос на смену забытого пароля
  def request_password_reset(email) do
    # Запрос юзера по почте
    case get_user_by_email(email) do
      nil ->
        {:error, :not_found}

      # Генерация 6 значного кода и временного ресет_токена для востановления пароля
      user ->
        code = :rand.uniform(900_000) + 99_999 |> Integer.to_string()

        claims = %{
          "user_id" => user.id,
          "reset_code" => code,
          "purpose" => "reset_password",
          "exp" => System.system_time(:second) + 300
        }

        case Token.generate_token(claims) do
          {:ok, reset_token, _} ->
            {:ok, %{code: code, reset_token: reset_token}}

          error ->
            error
        end
    end
  end

  # Проверка подтверждения нового пароля и проверка ресет_токена
  def reset_password(reset_token, code, new_password, new_password_confirmation) do
    cond do
      new_password != new_password_confirmation ->
        {:error, :password_confirmation_mismatch}

      true ->
        with {:ok, claims} <- Token.verify_token(reset_token),
             true <- claims["purpose"] == "reset_password",
             true <- to_string(claims["reset_code"]) == to_string(code),
             user when not is_nil(user) <- get_user(claims["user_id"]) do
          update_password(user, new_password)
        else
          false -> {:error, :invalid_code}
          nil -> {:error, :user_not_found}
          {:error, _reason} = err -> err
        end
    end
  end
end
