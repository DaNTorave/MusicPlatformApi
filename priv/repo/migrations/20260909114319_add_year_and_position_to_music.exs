defmodule MusicPlatformApi.Repo.Migrations.AddYearAndPositionToMusic do
  use Ecto.Migration

  def change do
    alter table(:albums) do
      add :release_year, :integer
    end

    alter table(:tracks) do
      add :release_year, :integer
      add :position, :integer, default: 1, null: false
    end

    create index(:tracks, [:album_id, :position])
  end
end
