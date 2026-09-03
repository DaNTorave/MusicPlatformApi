defmodule MusicPlatformApi.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :title, :string, null: false
      add :message, :text, null: false
      add :type, :string, default: "info", null: false
      add :is_read, :boolean, default: false, null: false
      add :entity_type, :string
      add :entity_id, :integer
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notifications, [:user_id])
    create index(:notifications, [:is_read])
    create index(:notifications, [:user_id, :is_read])
  end
end
