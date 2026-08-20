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
    |> validate_required([:login, :email, :nickname, :password])
    |> validate_length(:login, min: 3, max: 50)
    |> validate_length(:nickname, min: 2, max: 50)
    |> validate_email()
    |> validate_password()
    |> validate_role()
    |> unique_constraint(:login, name: :users_login_index)
    |> unique_constraint(:email, name: :users_email_index)
    |> put_password_hash()
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:login, :email, :nickname])
    |> validate_required([:login, :email, :nickname])
    |> validate_length(:login, min: 3, max: 50)
    |> validate_length(:nickname, min: 2, max: 50)
    |> validate_email()
    |> unique_constraint(:login, name: :users_login_index)
    |> unique_constraint(:email, name: :users_email_index)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "invalid email format")
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 6, max: 100)
  end

  defp validate_role(changeset) do
    changeset
    |> validate_inclusion(:role, ["member"], message: "role must be 'member'")
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
