defmodule MusicPlatformApi.Repo.Migrations.CreateFavoriteTracks do
  use Ecto.Migration

  def change do
    create table(:favorite_tracks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :track_id, references(:tracks, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:favorite_tracks, [:user_id])
    create index(:favorite_tracks, [:track_id])
    create unique_index(:favorite_tracks, [:user_id, :track_id], name: :user_track_favorite_unique)
  end
end
