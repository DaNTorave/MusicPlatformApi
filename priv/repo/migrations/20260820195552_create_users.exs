defmodule MusicPlatformApi.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :login, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :nickname, :string, null: true
      add :avatar, :string, null: true
      add :role, :string, default: "member", null: false
      add :is_premium, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:login], name: :users_login_index)
    create unique_index(:users, [:email], name: :users_email_index)
  end
end
