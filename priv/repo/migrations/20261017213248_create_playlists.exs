defmodule MusicPlatformApi.Repo.Migrations.CreatePlaylists do
  use Ecto.Migration

  def change do
    create table(:playlists) do
      add :title, :string, null: false
      add :cover, :string
      add :is_public, :boolean, default: true, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:playlists, [:user_id])
    create index(:playlists, [:is_public])

    create table(:playlist_tracks) do
      add :playlist_id, references(:playlists, on_delete: :delete_all), null: false
      add :track_id, references(:tracks, on_delete: :delete_all), null: false
      add :position, :integer, default: 1, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:playlist_tracks, [:playlist_id])
    create index(:playlist_tracks, [:track_id])
    create unique_index(:playlist_tracks, [:playlist_id, :track_id], name: :playlist_track_unique)
  end
end
