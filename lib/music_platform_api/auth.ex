# lib/music_platform_api/auth.ex

defmodule MusicPlatformApi.Auth do
  alias MusicPlatformApi.{Repo, User, Token}
  import Ecto.Query

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

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

  def generate_token(user) do
    claims = %{
      "user_id" => user.id,
      "login" => user.login,
      "email" => user.email,
      "role" => user.role,
      "exp" => System.system_time(:second) + 86400
    }

    case Token.generate_token(claims) do
      {:ok, token, _claims} -> token
      {:error, reason} -> {:error, reason}
    end
  end

  def verify_token(token) do
    case Token.verify_token(token) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> {:error, "Недействительный токен: #{reason}"}
    end
  end

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

  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  def update_password(%User{} = user, new_password) do
    changeset =
      user
      |> Ecto.Changeset.cast(%{password: new_password}, [:password])
      |> Ecto.Changeset.validate_length(:password, min: 6, max: 100)
      |> User.put_password_hash()

    Repo.update(changeset)
  end

  def get_user(id) do
    Repo.get(User, id)
  end

  def get_user_by_login(login) do
    Repo.get_by(User, login: login)
  end

  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def check_password(user, password) do
    User.valid_password?(user, password)
  end
end
