defmodule MusicPlatformApi.Repo.Migrations.FixUsersTable do
  use Ecto.Migration

  def up do
    result = execute("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users')")

    case result do
      %{rows: [[true]]} ->
        IO.puts("Таблица users уже существует")
      _ ->
        IO.puts("Создание таблицы users")
        create_users_table()
    end
  end

  def down do
    execute("DROP TABLE IF EXISTS users CASCADE")
  end

  defp create_users_table do
    create table(:users, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :login, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :nickname, :string
      add :avatar, :string
      add :role, :string, default: "member", null: false
      add :is_premium, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:login], name: :users_login_index)
    create unique_index(:users, [:email], name: :users_email_index)
  end
end
