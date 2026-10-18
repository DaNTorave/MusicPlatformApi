defmodule MusicPlatformApi.Music do
  import Ecto.Query
  alias MusicPlatformApi.Repo
  alias MusicPlatformApi.Music.{Artist, Album, Track, FavoriteTrack, Playlist, PlaylistTrack}
  alias MusicPlatformApi.Notifications.Notification

  # Сохранение файла на сервере
  def save_upload(%Plug.Upload{path: tmp_path, filename: filename}, subfolder) do
    ext = Path.extname(filename)
    unique_name = "#{Ecto.UUID.generate()}#{ext}"

    dest_dir = Path.expand("priv/static/uploads/#{subfolder}")
    File.mkdir_p!(dest_dir)
    dest_path = Path.join(dest_dir, unique_name)
    File.cp!(tmp_path, dest_path)

    {:ok, "/uploads/#{subfolder}/#{unique_name}", dest_path}
  end

  # Создание в БД исполнителя
  def create_artist(attrs, user_id) do
    %Artist{}
    |> Artist.changeset(Map.put(attrs, "creator_id", user_id))
    |> Repo.insert()
  end

  # Создание альбома с треками
  def create_album_with_tracks(%{"tracks" => tracks_params} = album_params, user_id) do
    Repo.transaction(fn ->
      album_year = parse_int(Map.get(album_params, "release_year"))
      album_params = Map.put(album_params, "release_year", if(album_year > 0, do: album_year, else: nil))

      album_changeset =
        %Album{}
        |> Album.changeset(Map.put(album_params, "creator_id", user_id))

      case Repo.insert(album_changeset) do
        {:ok, album} ->
          tracks_params
          |> Enum.with_index(1)
          |> Enum.each(fn {track_params, fallback_index} ->
            collab_ids =
              case Map.get(track_params, "collaborator_ids") do
                ids when is_list(ids) -> ids
                id when is_binary(id) or is_integer(id) -> [id]
                _ -> []
              end
              |> Enum.reject(&(&1 == "" or is_nil(&1)))

            duration = parse_int(Map.get(track_params, "duration_seconds"))
            is_cover = parse_boolean(Map.get(track_params, "is_cover"))
            orig_track_id = parse_nullable_id(Map.get(track_params, "original_track_id"))
            age_restriction = parse_boolean(Map.get(track_params, "age_restriction"))

            pos_val = parse_int(Map.get(track_params, "position"))
            position = if pos_val > 0, do: pos_val, else: fallback_index

            track_year_val = parse_int(Map.get(track_params, "release_year"))
            release_year = if track_year_val > 0, do: track_year_val, else: album.release_year

            track_attrs =
              track_params
              |> Map.put("album_id", album.id)
              |> Map.put("artist_id", album.artist_id)
              |> Map.put("creator_id", user_id)
              |> Map.put("is_single", false)
              |> Map.put("duration_seconds", duration)
              |> Map.put("is_cover", is_cover)
              |> Map.put("original_track_id", orig_track_id)
              |> Map.put("position", position)
              |> Map.put("release_year", release_year)
              |> Map.put("age_restriction", age_restriction)

            track =
              %Track{}
              |> Track.changeset(track_attrs)
              |> Repo.insert!()

            if collab_ids != [] do
              artists = Repo.all(from a in Artist, where: a.id in ^collab_ids)

              track
              |> Repo.preload(:collaborators)
              |> Ecto.Changeset.change()
              |> Ecto.Changeset.put_assoc(:collaborators, artists)
              |> Repo.update!()
            end
          end)

          album

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # Создание сингла
  def create_single(attrs, user_id) do
    duration = parse_int(Map.get(attrs, "duration_seconds"))
    is_cover = parse_boolean(Map.get(attrs, "is_cover"))
    orig_track_id = parse_nullable_id(Map.get(attrs, "original_track_id"))
    year = parse_int(Map.get(attrs, "release_year"))
    age_restriction = parse_boolean(Map.get(attrs, "age_restriction"))

    attrs =
      attrs
      |> Map.put("creator_id", user_id)
      |> Map.put("is_single", true)
      |> Map.put("album_id", nil)
      |> Map.put("duration_seconds", duration)
      |> Map.put("is_cover", is_cover)
      |> Map.put("original_track_id", orig_track_id)
      |> Map.put("position", 1)
      |> Map.put("release_year", if(year > 0, do: year, else: nil))
      |> Map.put("age_restriction", age_restriction)

    %Track{}
    |> Track.changeset(attrs)
    |> Repo.insert()
  end

  # Модерация контента
  def moderate_item(schema, id, status, comment) when schema in [Artist, Album, Track] do
    item_id = if is_binary(id), do: String.to_integer(id), else: id
    item = Repo.get!(schema, item_id)
    changeset = schema.moderation_changeset(item, %{status: status, moderation_comment: comment})

    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, updated_item} ->
          if schema == Album do
            from(t in Track, where: t.album_id == ^updated_item.id)
            |> Repo.update_all(set: [status: status, moderation_comment: comment])
          end

          notify_creator(schema, updated_item, status, comment)
          updated_item

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # Отправка уведомления по результату модерации
  def notify_creator(schema, item, status, comment) do
    item_name =
      case schema do
        Artist -> "Исполнитель \"#{item.name}\""
        Album -> "Альбом \"#{item.title}\""
        Track -> "Сингл \"#{item.title}\""
      end

    {title, type, message} =
      if status == "approved" do
        {"Материал одобрен!", "success", "Ваш #{item_name} успешно прошел модерацию и опубликован в каталоге."}
      else
        {"Материал отклонен", "error", "Ваш #{item_name} был отклонен модератором. Причина: #{comment || "Не указана"}"}
      end

    entity_type_str =
      schema
      |> Module.split()
      |> List.last()
      |> String.downcase()

    %Notification{}
    |> Notification.changeset(%{
      user_id: item.creator_id,
      title: title,
      message: message,
      type: type,
      entity_type: entity_type_str,
      entity_id: item.id
    })
    |> Repo.insert()
  end

  # Получение данных об исполнителе
  def get_artist_page(artist_id) do
    artist = Repo.get_by(Artist, id: artist_id, status: "approved")
    if is_nil(artist) do
      {:error, :not_found}
    else
      track_preloads = [:artist, :collaborators, original_track: [:artist, :album]]

      albums =
        Repo.all(
          from a in Album,
            where: a.artist_id == ^artist_id and a.status == "approved",
            order_by: [desc: a.release_year],
            preload: [
              tracks: ^from(t in Track,
                where: t.status == "approved",
                order_by: [asc: t.position, asc: t.id],
                preload: ^track_preloads
              )
            ]
        )

      singles =
        Repo.all(
          from t in Track,
            left_join: c in assoc(t, :collaborators),
            where: (t.artist_id == ^artist_id or c.id == ^artist_id) and t.is_single == true and t.status == "approved",
            distinct: true,
            order_by: [desc: t.release_year],
            preload: ^track_preloads
        )

      collab_tracks =
        Repo.all(
          from t in Track,
            join: c in assoc(t, :collaborators),
            where: c.id == ^artist_id and t.is_single == false and t.status == "approved",
            distinct: true,
            preload: [:artist, :collaborators, :album, original_track: [:artist]]
        )

      {:ok, %{artist: artist, albums: albums, singles: singles, collab_tracks: collab_tracks}}
    end
  end

  # Вспомогательные функции преобразования типов
  def parse_int(nil), do: 0
  def parse_int(val) when is_integer(val), do: val
  def parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      _ -> 0
    end
  end
  def parse_int(_), do: 0

  def parse_boolean(true), do: true
  def parse_boolean("true"), do: true
  def parse_boolean(1), do: true
  def parse_boolean("1"), do: true
  def parse_boolean(_), do: false

  def parse_nullable_id(nil), do: nil
  def parse_nullable_id(""), do: nil
  def parse_nullable_id(val) when is_integer(val), do: val
  def parse_nullable_id(val) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      _ -> nil
    end
  end
  def parse_nullable_id(_), do: nil

  def delete_file(nil), do: :ok
  def delete_file(""), do: :ok

  def delete_file(url_or_path) when is_binary(url_or_path) do
    if String.contains?(url_or_path, "default") or String.starts_with?(url_or_path, "http") do
      :ok
    else
      relative_path =
        if String.starts_with?(url_or_path, "/uploads/") do
          "priv/static" <> url_or_path
        else
          url_or_path
        end

      full_path = Path.expand(relative_path)

      case File.rm(full_path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} ->
          require Logger
          Logger.warning("Не удалось удалить файл #{full_path}: #{inspect(reason)}")
          :ok
      end
    end
  end

  # Переключение статуса избранного для трека
  def toggle_favorite(user_id, track_id) do
    case Repo.get_by(FavoriteTrack, user_id: user_id, track_id: track_id) do
      nil ->
        Repo.transaction(fn ->
          %FavoriteTrack{}
          |> FavoriteTrack.changeset(%{user_id: user_id, track_id: track_id})
          |> Repo.insert!()

          from(t in Track, where: t.id == ^track_id)
          |> Repo.update_all(inc: [likes_count: 1])

          :favorited
        end)

      fav ->
        Repo.transaction(fn ->
          Repo.delete!(fav)

          from(t in Track, where: t.id == ^track_id)
          |> Repo.update_all(inc: [likes_count: -1])

          :unfavorited
        end)
    end
  end

  # Получение списка избранных треков пользователя
  def list_user_favorites(user_id, limit \\ nil) do
    query =
      from t in Track,
        join: f in FavoriteTrack, on: f.track_id == t.id,
        where: f.user_id == ^user_id and t.status == "approved",
        order_by: [desc: f.inserted_at],
        preload: [:artist, :album, :collaborators, original_track: [:artist]]

    query = if limit, do: from(q in query, limit: ^limit), else: query
    Repo.all(query)
  end

  # Список идентификаторов избранных треков пользователя
  def list_user_favorite_ids(user_id) do
    from(f in FavoriteTrack, where: f.user_id == ^user_id, select: f.track_id)
    |> Repo.all()
  end

  # Предзагрузка треков и владельца для плейлиста
  defp preload_playlist_associations(playlist_or_playlists) do
    tracks_query =
      from t in Track,
        join: pt in PlaylistTrack,
        on: pt.track_id == t.id,
        where: t.status == "approved",
        order_by: [asc: pt.position, asc: pt.inserted_at],
        preload: [:artist, :album, :collaborators, original_track: [:artist, :album]]

    Repo.preload(playlist_or_playlists, [:user, tracks: tracks_query])
  end

  # Получение всех плейлистов текущего пользователя для страницы плейлистов
  def list_my_playlists(user_id) do
    from(p in Playlist,
      where: p.user_id == ^user_id,
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
    |> preload_playlist_associations()
  end

  # Получение публичных плейлистов пользователя для отображения в профиле
  def list_user_public_playlists(user_id) do
    from(p in Playlist,
      where: p.user_id == ^user_id and p.is_public == true,
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
    |> preload_playlist_associations()
  end

  # Получение плейлиста по идентификатору
  def get_playlist(playlist_id) do
    id = parse_nullable_id(playlist_id)

    if is_nil(id) do
      {:error, :not_found}
    else
      case Repo.get(Playlist, id) do
        nil ->
          {:error, :not_found}

        playlist ->
          {:ok, preload_playlist_associations(playlist)}
      end
    end
  end

  # Создание нового плейлиста
  def create_playlist(attrs, user_id) do
    is_public =
      if Map.has_key?(attrs, "is_public") do
        parse_boolean(Map.get(attrs, "is_public"))
      else
        true
      end

    clean_attrs =
      attrs
      |> Map.put("user_id", user_id)
      |> Map.put("is_public", is_public)

    case %Playlist{}
         |> Playlist.changeset(clean_attrs)
         |> Repo.insert() do
      {:ok, playlist} -> {:ok, preload_playlist_associations(playlist)}
      error -> error
    end
  end

  # Обновление параметров плейлиста
  def update_playlist(%Playlist{} = playlist, attrs) do
    update_map = %{}

    update_map =
      if Map.has_key?(attrs, "title") and String.trim(to_string(attrs["title"])) != "" do
        Map.put(update_map, :title, String.trim(to_string(attrs["title"])))
      else
        update_map
      end

    update_map =
      if Map.has_key?(attrs, "is_public") do
        Map.put(update_map, :is_public, parse_boolean(attrs["is_public"]))
      else
        update_map
      end

    update_map =
      if Map.has_key?(attrs, "cover") and not is_nil(attrs["cover"]) do
        Map.put(update_map, :cover, attrs["cover"])
      else
        update_map
      end

    case playlist
         |> Playlist.changeset(update_map)
         |> Repo.update() do
      {:ok, updated} -> {:ok, preload_playlist_associations(updated)}
      error -> error
    end
  end

  # Удаление плейлиста и его обложки
  def delete_playlist(%Playlist{} = playlist) do
    case Repo.delete(playlist) do
      {:ok, deleted} ->
        delete_file(deleted.cover)
        {:ok, deleted}

      error ->
        error
    end
  end

  # Добавление или удаление трека в плейлисте
  def toggle_track_in_playlist(playlist_id, track_id) do
    p_id = parse_int(playlist_id)
    t_id = parse_int(track_id)

    case Repo.get_by(PlaylistTrack, playlist_id: p_id, track_id: t_id) do
      nil ->
        max_pos =
          from(pt in PlaylistTrack,
            where: pt.playlist_id == ^p_id,
            select: max(pt.position)
          )
          |> Repo.one()

        next_pos = (max_pos || 0) + 1

        case %PlaylistTrack{}
             |> PlaylistTrack.changeset(%{
               playlist_id: p_id,
               track_id: t_id,
               position: next_pos
             })
             |> Repo.insert() do
          {:ok, _pt} -> {:ok, :added}
          {:error, changeset} -> {:error, changeset}
        end

      existing ->
        Repo.delete!(existing)
        {:ok, :removed}
    end
  end

  # Удаление трека из плейлиста
  def remove_track_from_playlist(playlist_id, track_id) do
    p_id = parse_int(playlist_id)
    t_id = parse_int(track_id)

    case Repo.get_by(PlaylistTrack, playlist_id: p_id, track_id: t_id) do
      nil ->
        {:error, :not_found}

      existing ->
        Repo.delete!(existing)
        {:ok, :removed}
    end
  end
end
