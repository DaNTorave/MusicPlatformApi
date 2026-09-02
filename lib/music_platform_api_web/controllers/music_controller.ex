defmodule MusicPlatformApiWeb.MusicController do
  use MusicPlatformApiWeb, :controller
  import Ecto.Query
  alias MusicPlatformApi.{Auth, Music, Repo}
  alias MusicPlatformApi.Music.{Artist, Track, Album}

  defp authenticate_staff(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) and user.role in ["admin", "moderator"] <- Auth.get_user_from_token(token) do
      {:ok, user}
    else
      _ -> {:error, :forbidden}
    end
  end

  def delete_artist(conn, %{"id" => id}) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) <- Auth.get_user_from_token(token),
         artist when not is_nil(artist) <- Repo.get(Artist, id) |> Repo.preload([:albums, :tracks]) do

      if user.role in ["admin", "moderator"] do
        Enum.each(artist.tracks || [], fn track ->
          if track.file_path && File.exists?(track.file_path) do
            File.rm(track.file_path)
          end
        end)

        if artist.avatar && File.exists?(artist.avatar) && not String.contains?(artist.avatar, "default") do
          File.rm(artist.avatar)
        end

        case Repo.delete(artist) do
          {:ok, _deleted} ->
            json(conn, %{success: true, message: "Исполнитель и все его релизы успешно удалены"})

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Ошибка удаления исполнителя", details: inspect(changeset.errors)})
        end
      else
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Недостаточно прав для удаления этого исполнителя"})
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Исполнитель не найден"})

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Требуется авторизация"})
    end
  end

  def delete_track(conn, %{"id" => id}) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) <- Auth.get_user_from_token(token),
         track when not is_nil(track) <- Repo.get(Track, id) do

      if user.role in ["admin", "moderator"] do
        if track.file_path && File.exists?(track.file_path) do
          File.rm(track.file_path)
        end

        case Repo.delete(track) do
          {:ok, _deleted} ->
            json(conn, %{success: true, message: "Трек успешно удален"})

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Ошибка удаления трека", details: inspect(changeset.errors)})
        end
      else
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Недостаточно прав для удаления этого трека"})
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Трек не найден"})

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Требуется авторизация"})
    end
  end

  def delete_album(conn, %{"id" => id}) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) <- Auth.get_user_from_token(token),
         album when not is_nil(album) <- Repo.get(Album, id) |> Repo.preload(:tracks) do

      if user.role in ["admin", "moderator"] do
        Enum.each(album.tracks || [], fn track ->
          if track.file_path && File.exists?(track.file_path) do
            File.rm(track.file_path)
          end
        end)

        case Repo.delete(album) do
          {:ok, _deleted} ->
            json(conn, %{success: true, message: "Альбом успешно удален"})

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Ошибка удаления альбома", details: inspect(changeset.errors)})
        end
      else
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Недостаточно прав для удаления этого альбома"})
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Альбом не найден"})

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Требуется авторизация"})
    end
  end

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
          limit: 10,
          preload: [:artist, :album]
      )
      |> Enum.map(fn t ->
        %{
          id: t.id,
          title: t.title,
          duration_seconds: t.duration_seconds,
          plays_count: t.plays_count,
          likes_count: t.likes_count,
          cover: Track.resolve_cover(t),
          artist: if(t.artist, do: %{id: t.artist.id, name: t.artist.name}, else: nil),
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
end
