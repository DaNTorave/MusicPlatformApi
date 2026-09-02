defmodule MusicPlatformApi.Music.Track do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :title,
             :audio_uuid,
             :duration_seconds,
             :plays_count,
             :likes_count,
             :is_single,
             :cover,
             :status,
             :moderation_comment,
             :artist_id,
             :album_id,
             :creator_id,
             :inserted_at,
             :updated_at
           ]}
  schema "tracks" do
    field :title, :string
    field :audio_uuid, Ecto.UUID
    field :file_path, :string
    field :duration_seconds, :integer, default: 0
    field :plays_count, :integer, default: 0
    field :likes_count, :integer, default: 0
    field :is_single, :boolean, default: false
    field :cover, :string
    field :status, :string, default: "pending"
    field :moderation_comment, :string

    field :effective_cover, :string, virtual: true

    belongs_to :artist, MusicPlatformApi.Music.Artist
    belongs_to :album, MusicPlatformApi.Music.Album
    belongs_to :creator, MusicPlatformApi.User, foreign_key: :creator_id

    many_to_many :collaborators, MusicPlatformApi.Music.Artist,
      join_through: "track_collaborators",
      on_replace: :delete

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(track, attrs) do
    track
    |> cast(attrs, [
      :title,
      :audio_uuid,
      :file_path,
      :duration_seconds,
      :is_single,
      :cover,
      :artist_id,
      :album_id,
      :creator_id
    ])
    |> validate_required([:title, :audio_uuid, :file_path, :artist_id, :creator_id])
  end

  def moderation_changeset(track, attrs) do
    track
    |> cast(attrs, [:status, :moderation_comment])
    |> validate_inclusion(:status, ["pending", "approved", "rejected"])
  end

  def resolve_cover(%__MODULE__{cover: cover, album: %{cover: _album_cover}}) when not is_nil(cover), do: cover
  def resolve_cover(%__MODULE__{cover: nil, album: %{cover: album_cover}}) when not is_nil(album_cover), do: album_cover
  def resolve_cover(%__MODULE__{cover: cover}) when not is_nil(cover), do: cover
  def resolve_cover(_), do: "/uploads/covers/default_cover.jpg"
end
