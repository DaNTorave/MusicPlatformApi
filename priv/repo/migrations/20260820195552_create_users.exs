defmodule MusicPlatformApi.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :login, :string, null: false
      add :email, :string, null: false
      add :nickname, :string, null: false
      add :role, :string, default: "member", null: false
      add :password_hash, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:login], name: :users_login_index)
    create unique_index(:users, [:email], name: :users_email_index)
  end
end
