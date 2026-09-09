defmodule MusicPlatformApiWeb.MusicController do
  use MusicPlatformApiWeb, :controller
  import Ecto.Query
  alias MusicPlatformApi.{Auth, Music, Repo}
  alias MusicPlatformApi.Music.{Artist, Track, Album}

  defp authenticate_user(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) <- Auth.get_user_from_token(token) do
      {:ok, user}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def get_artist(conn, %{"id" => id}) do
    case Music.get_artist_page(id) do
      {:ok, data} -> json(conn, %{success: true, data: data})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Артист не найден"})
    end
  end

  def list_artists(conn, _params) do
    artists = Repo.all(from a in Artist, where: a.status == "approved", order_by: [desc: a.plays_count, desc: a.inserted_at])
    json(conn, %{success: true, data: artists})
  end

  def create_artist(conn, params) do
    with {:ok, user} <- authenticate_user(conn) do
      params =
        if upload = params["avatar"] do
          {:ok, url, _path} = Music.save_upload(upload, "avatars")
          Map.put(params, "avatar", url)
        else
          params
        end

      case Music.create_artist(params, user.id) do
        {:ok, artist} -> conn |> put_status(:created) |> json(%{success: true, artist: artist})
        {:error, changeset} -> conn |> put_status(:bad_request) |> json(%{errors: changeset})
      end
    else
      {:error, :unauthorized} -> conn |> put_status(:unauthorized) |> json(%{error: "Требуется авторизация"})
    end
  end

  def create_single(conn, params) do
    with {:ok, user} <- authenticate_user(conn) do
      params =
        params
        |> maybe_save_file("cover", "covers")
        |> maybe_save_audio("audio")

      case Music.create_single(params, user.id) do
        {:ok, track} ->
          raw_collabs = Map.get(params, "collaborator_ids") || Map.get(params, "collaborator_ids[]")
          if raw_collabs do
            ids = if is_list(raw_collabs), do: raw_collabs, else: [raw_collabs]
            artists = Repo.all(from a in Artist, where: a.id in ^ids)
            track
            |> Repo.preload(:collaborators)
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.put_assoc(:collaborators, artists)
            |> Repo.update!()
          end

          conn |> put_status(:created) |> json(%{success: true, track: track})

        {:error, changeset} ->
          conn |> put_status(:bad_request) |> json(%{errors: changeset})
      end
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Требуется авторизация"})
    end
  end

  def create_album(conn, params) do
    with {:ok, user} <- authenticate_user(conn) do
      params = maybe_save_file(params, "cover", "covers")

      tracks_params =
        params
        |> Map.get("tracks", %{})
        |> Enum.map(fn {_idx, track} ->
          track
          |> maybe_save_file("cover", "covers")
          |> maybe_save_audio("audio")
        end)

      album_params = Map.put(params, "tracks", tracks_params)

      case Music.create_album_with_tracks(album_params, user.id) do
        {:ok, album} ->
          conn |> put_status(:created) |> json(%{success: true, album: album})

        {:error, changeset} ->
          conn |> put_status(:bad_request) |> json(%{errors: changeset})
      end
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Требуется авторизация"})
    end
  end

  def delete_track(conn, %{"id" => id}) do
    track = Repo.get!(Track, id)

    case Repo.delete(track) do
      {:ok, deleted_track} ->
        Music.delete_file(deleted_track.file_path)
        Music.delete_file(deleted_track.cover)

        json(conn, %{success: true, message: "Трек удален"})

      {:error, _changeset} ->
        conn |> put_status(:bad_request) |> json(%{error: "Ошибка удаления трека"})
    end
  end

  def delete_album(conn, %{"id" => id}) do
    album = Repo.get!(Album, id) |> Repo.preload(:tracks)

    case Repo.delete(album) do
      {:ok, deleted_album} ->
        Music.delete_file(deleted_album.cover)

        Enum.each(deleted_album.tracks, fn track ->
          Music.delete_file(track.file_path)
          Music.delete_file(track.cover)
        end)

        json(conn, %{success: true, message: "Альбом и треки удалены"})

      {:error, _} ->
        conn |> put_status(:bad_request) |> json(%{error: "Ошибка удаления альбома"})
    end
  end

  def delete_artist(conn, %{"id" => id}) do
    artist =
      Artist
      |> Repo.get!(id)
      |> Repo.preload([:albums, :tracks])

    case Repo.delete(artist) do
      {:ok, deleted_artist} ->
        Music.delete_file(deleted_artist.avatar)

        Enum.each(deleted_artist.albums, fn album ->
          Music.delete_file(album.cover)
        end)

        Enum.each(deleted_artist.tracks, fn track ->
          Music.delete_file(track.file_path)
          Music.delete_file(track.cover)
        end)

        json(conn, %{success: true, message: "Артист удален"})

      {:error, _} ->
        conn |> put_status(:bad_request) |> json(%{error: "Ошибка удаления артиста"})
    end
  end

  defp maybe_save_file(params, key, folder) do
    if upload = params[key] do
      {:ok, url, _} = Music.save_upload(upload, folder)
      Map.put(params, key, url)
    else
      params
    end
  end

  defp maybe_save_audio(params, key) do
    if upload = params[key] do
      {:ok, _url, dest_path} = Music.save_upload(upload, "tracks")
      params
      |> Map.put("file_path", dest_path)
      |> Map.put("audio_uuid", Ecto.UUID.generate())
    else
      params
    end
  end

  def top_tracks(conn, _params) do
    tracks =
      Repo.all(
        from t in Track,
          where: t.status == "approved",
          order_by: [desc: t.plays_count, desc: t.inserted_at],
          limit: 100,
          preload: [:artist, :album, :collaborators]
      )
      |> Enum.map(fn t ->
        %{
          id: t.id,
          title: t.title,
          duration_seconds: t.duration_seconds || 0,
          plays_count: t.plays_count || 0,
          likes_count: t.likes_count || 0,
          cover: Track.resolve_cover(t),
          artist: if(t.artist, do: %{id: t.artist.id, name: t.artist.name}, else: nil),
          collaborators: Enum.map(t.collaborators || [], &%{id: &1.id, name: &1.name}),
          album_id: t.album_id
        }
      end)

    json(conn, %{success: true, data: tracks})
  end

  def top_artists(conn, _params) do
    artists =
      Repo.all(
        from a in Artist,
          where: a.status == "approved",
          order_by: [desc: a.plays_count, desc: a.inserted_at],
          limit: 10
      )

    json(conn, %{success: true, data: artists})
  end

  def get_track(conn, %{"id" => id}) do
    track =
      MusicPlatformApi.Music.Track
      |> MusicPlatformApi.Repo.get(id)
      |> MusicPlatformApi.Repo.preload([:artist, :album, :collaborators, original_track: [:artist, :album]])

    case track do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Трек не найден"})

      track ->
        json(conn, %{track: track})
    end
  end
end
