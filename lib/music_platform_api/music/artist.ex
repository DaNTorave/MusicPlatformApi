defmodule MusicPlatformApi.Music.Artist do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :avatar,
             :genre,
             :plays_count,
             :likes_count,
             :status,
             :moderation_comment,
             :creator_id,
             :inserted_at,
             :updated_at
           ]}
  schema "artists" do
    field :name, :string
    field :avatar, :string
    field :genre, :string
    field :plays_count, :integer, default: 0
    field :likes_count, :integer, default: 0
    field :status, :string, default: "pending"
    field :moderation_comment, :string

    belongs_to :creator, MusicPlatformApi.User, foreign_key: :creator_id
    has_many :albums, MusicPlatformApi.Music.Album
    has_many :tracks, MusicPlatformApi.Music.Track

    many_to_many :collab_tracks, MusicPlatformApi.Music.Track,
      join_through: "track_collaborators"

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(artist, attrs) do
    artist
    |> cast(attrs, [:name, :avatar, :genre, :creator_id])
    |> validate_required([:name, :genre, :creator_id])
    |> validate_length(:name, min: 1, max: 100)
  end

  def moderation_changeset(artist, attrs) do
    artist
    |> cast(attrs, [:status, :moderation_comment])
    |> validate_inclusion(:status, ["pending", "approved", "rejected"])
  end
end
