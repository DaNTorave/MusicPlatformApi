defmodule MusicPlatformApi.Repo.Migrations.CreateArtists do
  use Ecto.Migration

  def change do
    create table(:artists) do
      add :name, :string, null: false
      add :avatar, :string
      add :genre, :string, null: false
      add :plays_count, :bigint, default: 0, null: false
      add :likes_count, :integer, default: 0, null: false
      add :status, :string, default: "pending", null: false
      add :moderation_comment, :text
      add :creator_id, references(:users, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:artists, [:creator_id])
    create index(:artists, [:status])
    create index(:artists, [:genre])
  end
end
