defmodule MusicPlatformApi.Music.Album do
  use Ecto.Schema
  import Ecto.Changeset

  schema "albums" do
    field :title, :string
    field :cover, :string
    field :likes_count, :integer, default: 0
    field :status, :string, default: "pending"
    field :moderation_comment, :string

    belongs_to :artist, MusicPlatformApi.Music.Artist
    belongs_to :creator, MusicPlatformApi.User, foreign_key: :creator_id
    has_many :tracks, MusicPlatformApi.Music.Track

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(album, attrs) do
    album
    |> cast(attrs, [:title, :cover, :artist_id, :creator_id])
    |> validate_required([:title, :cover, :artist_id, :creator_id])
  end

  def moderation_changeset(album, attrs) do
    album
    |> cast(attrs, [:status, :moderation_comment])
    |> validate_inclusion(:status, ["pending", "approved", "rejected"])
  end
end

defimpl Jason.Encoder, for: MusicPlatformApi.Music.Album do
  def encode(album, opts) do
    base = %{
      id: album.id,
      title: album.title,
      cover: album.cover,
      likes_count: album.likes_count,
      status: album.status,
      moderation_comment: album.moderation_comment,
      artist_id: album.artist_id,
      creator_id: album.creator_id,
      inserted_at: album.inserted_at,
      updated_at: album.updated_at
    }

    result =
      case album.tracks do
        %Ecto.Association.NotLoaded{} -> base
        tracks when is_list(tracks) -> Map.put(base, :tracks, tracks)
        _ -> base
      end

    Jason.Encode.map(result, opts)
  end
end
