defmodule MusicPlatformApi.Repo.Migrations.CreateTracks do
  use Ecto.Migration

  def change do
    create table(:tracks) do
      add :title, :string, null: false
      add :audio_uuid, :uuid, null: false
      add :file_path, :string, null: false
      add :duration_seconds, :integer, default: 0
      add :plays_count, :bigint, default: 0, null: false
      add :likes_count, :integer, default: 0, null: false
      add :is_single, :boolean, default: false, null: false
      
      add :cover, :string
      add :status, :string, default: "pending", null: false
      add :moderation_comment, :text

      add :artist_id, references(:artists, on_delete: :delete_all), null: false
      add :album_id, references(:albums, on_delete: :delete_all)
      add :creator_id, references(:users, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tracks, [:artist_id])
    create index(:tracks, [:album_id])
    create index(:tracks, [:creator_id])
    create index(:tracks, [:status])
    create unique_index(:tracks, [:audio_uuid])
  end
end
