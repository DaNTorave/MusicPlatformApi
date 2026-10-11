defmodule MusicPlatformApi.Music do
  import Ecto.Query
  alias MusicPlatformApi.Repo
  alias MusicPlatformApi.Music.{Artist, Album, Track}
  alias MusicPlatformApi.Notifications.Notification
  alias MusicPlatformApi.Music.FavoriteTrack

  # Сохранение файла на сервере
  def save_upload(%Plug.Upload{path: tmp_path, filename: filename}, subfolder) do
    # Извелечение расширения файла
    ext = Path.extname(filename)
    # Генерация уникального названия файла
    unique_name = "#{Ecto.UUID.generate()}#{ext}"

    # Куда сохранять
    dest_dir = Path.expand("priv/static/uploads/#{subfolder}")
    # Создание папки, если нет
    File.mkdir_p!(dest_dir)
    dest_path = Path.join(dest_dir, unique_name)
    # Копирование из временого plug в хранилище
    File.cp!(tmp_path, dest_path)

    {:ok, "/uploads/#{subfolder}/#{unique_name}", dest_path}
  end

  # Создание в бд исполнителя
  def create_artist(attrs, user_id) do
    %Artist{}
    # Внедрение айдишника создателя
    |> Artist.changeset(Map.put(attrs, "creator_id", user_id))
    |> Repo.insert()
  end

  # Создание альбома с треками
  def create_album_with_tracks(%{"tracks" => tracks_params} = album_params, user_id) do
    # На случай падения откат
    Repo.transaction(fn ->
      # Если проблемы с годом релиза, то пустое значение
      album_year = parse_int(Map.get(album_params, "release_year"))
      album_params = Map.put(album_params, "release_year", if(album_year > 0, do: album_year, else: nil))

      album_changeset =
        %Album{}
        # Опять внедрение айдишника
        |> Album.changeset(Map.put(album_params, "creator_id", user_id))

      case Repo.insert(album_changeset) do
        {:ok, album} ->
          tracks_params
          |> Enum.with_index(1)
          |> Enum.each(fn {track_params, fallback_index} ->
            # Приведение айдишников соавторов у трека к норме
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

            # Положение в альбоме
            pos_val = parse_int(Map.get(track_params, "position"))
            position = if pos_val > 0, do: pos_val, else: fallback_index

            # Год релиза
            track_year_val = parse_int(Map.get(track_params, "release_year"))
            release_year = if track_year_val > 0, do: track_year_val, else: album.release_year

            # Связка с таблицей треков методом "многие ко многим"
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

            # Если с соавторами
            if collab_ids != [] do
              artists = Repo.all(from a in Artist, where: a.id in ^collab_ids)

              track
              |> Repo.preload(:collaborators) # Загрузка действующей связи
              |> Ecto.Changeset.change()
              |> Ecto.Changeset.put_assoc(:collaborators, artists) # Настройка связи "многие ко многим"
              |> Repo.update!()
            end
          end)

          album

        {:error, changeset} ->
          # Сам откат
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

  # Модерация контента только на артиста, альбом и трек
  def moderate_item(schema, id, status, comment) when schema in [Artist, Album, Track] do
    item_id = if is_binary(id), do: String.to_integer(id), else: id
    item = Repo.get!(schema, item_id)
    changeset = schema.moderation_changeset(item, %{status: status, moderation_comment: comment})

    # Транзакция на случай падения
    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, updated_item} ->
          if schema == Album do
            from(t in Track, where: t.album_id == ^updated_item.id)
            |> Repo.update_all(set: [status: status, moderation_comment: comment])
          end

          # Запись в таблице уведомлений у юзера
          notify_creator(schema, updated_item, status, comment)
          updated_item

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # Возрат уведомления по результату модерации
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

    # Переделка в тип сущности
    entity_type_str =
      schema
      |> Module.split()
      |> List.last()
      |> String.downcase()

    # Заброс в БД
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

      # Показ одобренных альбомов
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

      # Показ одобренных синглов
      singles =
        Repo.all(
          from t in Track,
            left_join: c in assoc(t, :collaborators),
            where: (t.artist_id == ^artist_id or c.id == ^artist_id) and t.is_single == true and t.status == "approved",
            distinct: true,
            order_by: [desc: t.release_year],
            preload: ^track_preloads
        )

      # Показ участия в релизах у других
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

  # Вспомогательное
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

  # Переключение лайка (добавить и удалить) с обновлением счетчика likes_count
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

  # Список ID избранных треков для подсветки активных сердечек на клиенте
  def list_user_favorite_ids(user_id) do
    from(f in FavoriteTrack, where: f.user_id == ^user_id, select: f.track_id)
    |> Repo.all()
  end
end
