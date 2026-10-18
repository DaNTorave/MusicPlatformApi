defmodule MusicPlatformApi.Music.PlaylistTrack do
  use Ecto.Schema
  import Ecto.Changeset

  schema "playlist_tracks" do
    field :position, :integer, default: 1

    belongs_to :playlist, MusicPlatformApi.Music.Playlist
    belongs_to :track, MusicPlatformApi.Music.Track

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(playlist_track, attrs) do
    playlist_track
    |> cast(attrs, [:playlist_id, :track_id, :position])
    |> validate_required([:playlist_id, :track_id])
    |> unique_constraint([:playlist_id, :track_id], name: :playlist_track_unique)
  end
end
