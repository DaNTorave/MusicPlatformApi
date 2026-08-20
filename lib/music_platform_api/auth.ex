defmodule MusicPlatformApi.Auth do
  alias MusicPlatformApi.{Repo, User}
  alias Joken, as: Token
  import Ecto.Query

  @secret Application.compile_env(:music_platform_api, MusicPlatformApiWeb.Endpoint)[:secret_key_base]

  # Регистрация пользователя
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  # Аутентификация по логину/почте и паролю
  def authenticate(login_or_email, password) do
    user = get_user_by_login_or_email(login_or_email)

    case user do
      nil -> {:error, "Invalid credentials"}
      user ->
        if User.valid_password?(user, password) do
          {:ok, user}
        else
          {:error, "Invalid credentials"}
        end
    end
  end

  # Генерация JWT токена
  def generate_token(user) do
    claims = %{
      user_id: user.id,
      login: user.login,
      email: user.email,
      role: user.role
    }

    case Token.generate_and_sign(claims, %{}, secret: @secret, algorithm: :HS256) do
      {:ok, token, _claims} -> token
      {:error, reason} -> {:error, reason}
    end
  end

  # Проверка JWT токена
  def verify_token(token) do
    case Token.verify(token, secret: @secret, algorithm: :HS256) do
      {:ok, claims} -> {:ok, claims}
      {:error, _} -> {:error, "Invalid token"}
    end
  end

  # Получение пользователя по токену
  def get_user_from_token(token) do
    case verify_token(token) do
      {:ok, claims} ->
        Repo.get(User, claims["user_id"])
      {:error, _} -> nil
    end
  end

  defp get_user_by_login_or_email(login_or_email) do
    query = from u in User,
            where: u.login == ^login_or_email or u.email == ^login_or_email,
            limit: 1

    Repo.one(query)
  end

  # Обновление пользователя
  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  # Обновление пароля
  def update_password(%User{} = user, new_password) do
    changeset =
      user
      |> Ecto.Changeset.cast(%{password: new_password}, [:password])
      |> Ecto.Changeset.validate_length(:password, min: 6, max: 100)
      |> User.put_password_hash()

    Repo.update(changeset)
  end

  # Получение пользователя по ID
  def get_user(id) do
    Repo.get(User, id)
  end

  # Получение пользователя по логину
  def get_user_by_login(login) do
    Repo.get_by(User, login: login)
  end

  # Получение пользователя по почте
  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  # Проверка пароля без аутентификации
  def check_password(user, password) do
    User.valid_password?(user, password)
  end
end
