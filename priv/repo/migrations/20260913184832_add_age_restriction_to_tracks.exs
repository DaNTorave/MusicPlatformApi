defmodule MusicPlatformApi.Repo.Migrations.AddAgeRestrictionToTracks do
  use Ecto.Migration

  def change do
    alter table(:tracks) do
      add :age_restriction, :boolean, default: false, null: false
    end
  end
end
