defmodule MusicPlatformApi.Repo.Migrations.AddCoverFieldsToTracks do
  use Ecto.Migration

  def change do
    alter table(:tracks) do
      add :is_cover, :boolean, default: false, null: false
      add :original_track_id, references(:tracks, on_delete: :nilify_all)
    end

    create index(:tracks, [:original_track_id])
  end
end
