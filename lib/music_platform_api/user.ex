defmodule MusicPlatformApi.User do
  use Ecto.Schema
  import Ecto.Changeset
  import Pbkdf2

  @derive {Jason.Encoder, only: [:id, :login, :email, :nickname, :role, :inserted_at, :updated_at]}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :login, :string
    field :email, :string
    field :nickname, :string
    field :role, :string, default: "member"
    field :password_hash, :string
    field :password, :string, virtual: true

    timestamps(type: :utc_datetime_usec)
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:login, :email, :nickname, :password])
    |> validate_required([:login, :email, :nickname, :password],
         message: "не может быть пустым")
    |> validate_length(:login, min: 3, max: 50,
         message: "должен содержать от 3 до 50 символов")
    |> validate_length(:nickname, min: 2, max: 50,
         message: "должен содержать от 2 до 50 символов")
    |> validate_email()
    |> validate_password()
    |> validate_role()
    |> unique_constraint(:login, name: :users_login_index,
         message: "уже занят")
    |> unique_constraint(:email, name: :users_email_index,
         message: "уже занят")
    |> put_password_hash()
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:login, :email, :nickname])
    |> validate_required([:login, :email, :nickname],
         message: "не может быть пустым")
    |> validate_length(:login, min: 3, max: 50,
         message: "должен содержать от 3 до 50 символов")
    |> validate_length(:nickname, min: 2, max: 50,
         message: "должен содержать от 2 до 50 символов")
    |> validate_email()
    |> unique_constraint(:login, name: :users_login_index,
         message: "уже занят")
    |> unique_constraint(:email, name: :users_email_index,
         message: "уже занят")
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email], message: "не может быть пустым")
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
         message: "неверный формат email")
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password], message: "не может быть пустым")
    |> validate_length(:password, min: 6, max: 100,
         message: "должен содержать от 6 до 100 символов")
  end

  defp validate_role(changeset) do
    changeset
    |> validate_inclusion(:role, ["member"],
         message: "роль должна быть 'member'")
  end

  def put_password_hash(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, hash_pwd_salt(password))
    end
  end

  def valid_password?(%{password_hash: hash}, password) do
    verify_pass(password, hash)
  end
end
