defmodule MusicPlatformApi.Music.Playlist do
  use Ecto.Schema
  import Ecto.Changeset

  schema "playlists" do
    field :title, :string
    field :cover, :string
    field :is_public, :boolean, default: true

    belongs_to :user, MusicPlatformApi.User
    has_many :playlist_tracks, MusicPlatformApi.Music.PlaylistTrack

    many_to_many :tracks, MusicPlatformApi.Music.Track,
      join_through: "playlist_tracks",
      on_replace: :delete

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(playlist, attrs) do
    playlist
    |> cast(attrs, [:title, :cover, :is_public, :user_id])
    |> validate_required([:title, :user_id])
    |> validate_length(:title, min: 1, max: 120)
  end
end

defimpl Jason.Encoder, for: MusicPlatformApi.Music.Playlist do
  def encode(playlist, opts) do
    tracks_list =
      case playlist.tracks do
        %Ecto.Association.NotLoaded{} -> []
        list when is_list(list) -> list
        _ -> []
      end

    owner =
      case playlist.user do
        %Ecto.Association.NotLoaded{} ->
          nil

        nil ->
          nil

        u ->
          %{
            id: u.id,
            login: u.login,
            nickname: u.nickname,
            avatar: u.avatar
          }
      end

    has_age_restriction = Enum.any?(tracks_list, & &1.age_restriction)

    base = %{
      id: playlist.id,
      title: playlist.title,
      cover: playlist.cover,
      is_public: playlist.is_public,
      user_id: playlist.user_id,
      owner: owner,
      tracks_count: length(tracks_list),
      track_ids: Enum.map(tracks_list, & &1.id),
      has_age_restriction: has_age_restriction,
      inserted_at: playlist.inserted_at,
      updated_at: playlist.updated_at
    }

    result =
      case playlist.tracks do
        %Ecto.Association.NotLoaded{} -> base
        list when is_list(list) -> Map.put(base, :tracks, list)
        _ -> base
      end

    Jason.Encode.map(result, opts)
  end
end
