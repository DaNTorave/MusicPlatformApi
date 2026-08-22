# lib/music_platform_api/auth.ex

defmodule MusicPlatformApi.Auth do
  alias MusicPlatformApi.{Repo, User, Token}
  import Ecto.Query

  def register_user(attrs) do
    attrs =
      case Map.get(attrs, "nickname") do
        nil ->
          Map.put(attrs, "nickname", generate_unique_nickname())
        "" ->
          Map.put(attrs, "nickname", generate_unique_nickname())
        _ ->
          attrs
      end

    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  defp generate_unique_nickname do
    random_suffix = :rand.uniform(999_999) |> Integer.to_string() |> String.pad_leading(6, "0")
    base_nickname = "user#{random_suffix}"

    case get_user_by_nickname(base_nickname) do
      nil -> base_nickname
      _ -> generate_unique_nickname()
    end
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

  def get_user_by_nickname(nickname) do
    Repo.get_by(User, nickname: nickname)
  end

  def check_password(user, password) do
    User.valid_password?(user, password)
  end

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
end
