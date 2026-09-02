defmodule MusicPlatformApi.Repo.Migrations.CreateAlbums do
  use Ecto.Migration

  def change do
    create table(:albums) do
      add :title, :string, null: false
      add :cover, :string, null: false
      add :likes_count, :integer, default: 0, null: false
      add :status, :string, default: "pending", null: false
      add :moderation_comment, :text

      add :artist_id, references(:artists, on_delete: :delete_all), null: false
      add :creator_id, references(:users, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:albums, [:artist_id])
    create index(:albums, [:creator_id])
    create index(:albums, [:status])
  end
end
