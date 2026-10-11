defmodule MusicPlatformApi.Music.FavoriteTrack do
  use Ecto.Schema
  import Ecto.Changeset

  schema "favorite_tracks" do
    belongs_to :user, MusicPlatformApi.User
    belongs_to :track, MusicPlatformApi.Music.Track

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:user_id, :track_id])
    |> validate_required([:user_id, :track_id])
    |> unique_constraint([:user_id, :track_id], name: :user_track_favorite_unique)
  end
end
