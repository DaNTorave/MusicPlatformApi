defmodule MusicPlatformApi.Repo.Migrations.CreateTrackCollaborators do
  use Ecto.Migration

  def change do
    create table(:track_collaborators, primary_key: false) do
      add :track_id, references(:tracks, on_delete: :delete_all), null: false
      add :artist_id, references(:artists, on_delete: :delete_all), null: false
    end

    create index(:track_collaborators, [:track_id])
    create index(:track_collaborators, [:artist_id])
    create unique_index(:track_collaborators, [:track_id, :artist_id])
  end
end
