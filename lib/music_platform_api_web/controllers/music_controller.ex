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

  # Показ страницы артиста
  def get_artist(conn, %{"id" => id}) do
    case Music.get_artist_page(id) do
      {:ok, data} -> json(conn, %{success: true, data: data})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Артист не найден"})
    end
  end

  # Список артистов по популярности
  def list_artists(conn, _params) do
    artists = Repo.all(from a in Artist, where: a.status == "approved", order_by: [desc: a.plays_count, desc: a.inserted_at])
    json(conn, %{success: true, data: artists})
  end

  # Создание профиля артиста
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

  # Создание сингла, включает файл, связь с соавторами
  def create_single(conn, params) do
    with {:ok, user} <- authenticate_user(conn) do
      params =
        params
        |> maybe_save_file("cover", "covers")
        |> maybe_save_audio("audio")

      case Music.create_single(params, user.id) do
        {:ok, track} ->
          # Привязка соавторов через many-to-many
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
      # Сохранение обложки альбома
      params = maybe_save_file(params, "cover", "covers")

      # Обход списка треков и сохранение медиафайлов для них
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

  # Удаление трека полностью
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

  # Удаление альбома полностью
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

  # Удаление артиста полностью
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

  # Топ 100 треков по прослушиваниям
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
          album_id: t.album_id,
          age_restriction: t.age_restriction
        }
      end)

    json(conn, %{success: true, data: tracks})
  end

  # Топ 10 артистов по прослушиванию на их треках
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

  # Получить трек
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

  # Список избранного с ограничением
  def list_favorites(conn, params) do
    with {:ok, user} <- authenticate_user(conn) do
      limit =
        case params["limit"] do
          nil -> nil
          val -> String.to_integer(val)
        end

      tracks = Music.list_user_favorites(user.id, limit)
      json(conn, %{success: true, data: tracks})
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Требуется авторизация"})
    end
  end

  # Быстрого определение, добавлен ли трек
  def favorite_ids(conn, _params) do
    with {:ok, user} <- authenticate_user(conn) do
      ids = Music.list_user_favorite_ids(user.id)
      json(conn, %{success: true, data: ids})
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Требуется авторизация"})
    end
  end

  # Добавление и удаление трека из избранного
  def toggle_favorite(conn, %{"track_id" => track_id}) do
    with {:ok, user} <- authenticate_user(conn) do
      track_id = if is_binary(track_id), do: String.to_integer(track_id), else: track_id

      case Music.toggle_favorite(user.id, track_id) do
        {:ok, status} ->
          json(conn, %{success: true, status: status, is_favorite: status == :favorited})

        {:error, reason} ->
          conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
      end
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Требуется авторизация"})
    end
  end
end
