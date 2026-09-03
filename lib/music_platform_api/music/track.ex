defmodule MusicPlatformApi.Music.Track do
  use Ecto.Schema
  import Ecto.Changeset

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

    field :is_cover, :boolean, default: false

    field :effective_cover, :string, virtual: true

    belongs_to :artist, MusicPlatformApi.Music.Artist
    belongs_to :album, MusicPlatformApi.Music.Album
    belongs_to :creator, MusicPlatformApi.User, foreign_key: :creator_id
    belongs_to :original_track, MusicPlatformApi.Music.Track, foreign_key: :original_track_id

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
      :creator_id,
      :is_cover,
      :original_track_id
    ])
    |> validate_required([:title, :audio_uuid, :file_path, :artist_id, :creator_id])
  end

  def moderation_changeset(track, attrs) do
    track
    |> cast(attrs, [:status, :moderation_comment, :is_cover, :original_track_id, :title])
    |> validate_inclusion(:status, ["pending", "approved", "rejected"])
  end

  def resolve_cover(%__MODULE__{cover: cover, album: %{cover: _album_cover}}) when not is_nil(cover), do: cover
  def resolve_cover(%__MODULE__{cover: nil, album: %{cover: album_cover}}) when not is_nil(album_cover), do: album_cover
  def resolve_cover(%__MODULE__{cover: cover}) when not is_nil(cover), do: cover
  def resolve_cover(_), do: "/uploads/covers/default_cover.jpg"

  defimpl Jason.Encoder, for: MusicPlatformApi.Music.Track do
    def encode(track, opts) do
      resolved_cover =
        case {track.cover, track.album} do
          {cover, _} when not is_nil(cover) and cover != "" -> cover
          {_, %{cover: album_cover}} when not is_nil(album_cover) -> album_cover
          _ -> track.cover
        end

      base = %{
        id: track.id,
        title: track.title,
        audio_uuid: track.audio_uuid,
        duration_seconds: track.duration_seconds,
        plays_count: track.plays_count,
        likes_count: track.likes_count,
        is_single: track.is_single,
        cover: resolved_cover,
        status: track.status,
        moderation_comment: track.moderation_comment,
        artist_id: track.artist_id,
        album_id: track.album_id,
        creator_id: track.creator_id,
        is_cover: track.is_cover,
        original_track_id: track.original_track_id,
        inserted_at: track.inserted_at,
        updated_at: track.updated_at
      }

      base =
        case track.artist do
          %Ecto.Association.NotLoaded{} -> base
          nil -> base
          artist -> Map.put(base, :artist, %{id: artist.id, name: artist.name})
        end

      base =
        case track.album do
          %Ecto.Association.NotLoaded{} -> base
          nil -> base
          album -> Map.put(base, :album, %{id: album.id, title: album.title, cover: album.cover})
        end

      base =
        case track.collaborators do
          %Ecto.Association.NotLoaded{} -> base
          nil -> Map.put(base, :collaborators, [])
          collabs -> Map.put(base, :collaborators, Enum.map(collabs, &%{id: &1.id, name: &1.name}))
        end

      base =
        case track.original_track do
          %Ecto.Association.NotLoaded{} -> base
          nil -> Map.put(base, :original_track, nil)
          orig ->
            orig_artist =
              case orig.artist do
                %Ecto.Association.NotLoaded{} -> nil
                nil -> nil
                a -> %{id: a.id, name: a.name}
              end

            orig_cover =
              case {orig.cover, orig.album} do
                {c, _} when not is_nil(c) and c != "" -> c
                {_, %{cover: album_cover}} when not is_nil(album_cover) and album_cover != "" -> album_cover
                _ -> orig.cover
              end

            Map.put(base, :original_track, %{
              id: orig.id,
              title: orig.title,
              cover: orig_cover,
              artist: orig_artist
            })
        end

      Jason.Encode.map(base, opts)
    end
  end
end
