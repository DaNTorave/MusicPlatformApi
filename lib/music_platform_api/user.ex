defmodule MusicPlatformApi.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, []}
  @derive {Phoenix.Param, key: :id}

  @registration_fields [:login, :email, :password, :nickname, :avatar, :is_premium, :role]
  @required_fields [:login, :email, :password]

  schema "users" do
    field :login, :string
    field :email, :string
    field :password_hash, :string
    field :nickname, :string
    field :avatar, :string
    field :is_premium, :boolean, default: false
    field :role, :string, default: "member"
    field :password, :string, virtual: true

    timestamps(type: :utc_datetime_usec)
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, @registration_fields)
    |> validate_required(@required_fields)
    |> validate_length(:login, min: 3, max: 50)
    |> validate_length(:email, max: 100)
    |> validate_format(:email, ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,
        message: "неверный формат email")
    |> validate_length(:nickname, max: 50)
    |> validate_length(:password, min: 6, max: 100)
    |> validate_inclusion(:role, ["member", "admin", "moderator"],
        message: "роль должна быть 'member', 'admin' или 'moderator'")
    |> validate_inclusion(:is_premium, [true, false],
        message: "должно быть true или false")
    |> unique_constraint(:login, name: :users_login_index, message: "уже занят")
    |> unique_constraint(:email, name: :users_email_index, message: "уже занят")
    |> put_password_hash()
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:login, :email, :nickname, :avatar, :is_premium])
    |> validate_length(:login, min: 3, max: 50)
    |> validate_length(:email, max: 100)
    |> validate_format(:email, ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,
        message: "неверный формат email")
    |> validate_length(:nickname, min: 1, max: 50)
    |> unique_constraint(:login, name: :users_login_index, message: "уже занят")
    |> unique_constraint(:email, name: :users_email_index, message: "уже занят")
    |> validate_inclusion(:is_premium, [true, false],
        message: "должно быть true или false")
  end

  def put_password_hash(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    change(changeset, password_hash: Pbkdf2.hash_pwd_salt(password))
  end

  def put_password_hash(changeset), do: changeset

  def valid_password?(user, password) do
    Pbkdf2.verify_pass(password, user.password_hash)
  end
end
