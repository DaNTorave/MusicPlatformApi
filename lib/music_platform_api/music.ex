defmodule MusicPlatformApi.Music do
  import Ecto.Query
  alias MusicPlatformApi.Repo
  alias MusicPlatformApi.Music.{Artist, Album, Track}
  alias MusicPlatformApi.Notifications.Notification

  def save_upload(%Plug.Upload{path: tmp_path, filename: filename}, subfolder) do
    ext = Path.extname(filename)
    unique_name = "#{Ecto.UUID.generate()}#{ext}"

    dest_dir = Path.expand("priv/static/uploads/#{subfolder}")
    File.mkdir_p!(dest_dir)
    dest_path = Path.join(dest_dir, unique_name)
    File.cp!(tmp_path, dest_path)

    {:ok, "/uploads/#{subfolder}/#{unique_name}", dest_path}
  end

  def create_artist(attrs, user_id) do
    %Artist{}
    |> Artist.changeset(Map.put(attrs, "creator_id", user_id))
    |> Repo.insert()
  end

  def create_album_with_tracks(%{"tracks" => tracks_params} = album_params, user_id) do
    Repo.transaction(fn ->
      album_changeset =
        %Album{}
        |> Album.changeset(Map.put(album_params, "creator_id", user_id))

      case Repo.insert(album_changeset) do
        {:ok, album} ->
          Enum.each(tracks_params, fn track_params ->
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

            track_attrs =
              track_params
              |> Map.put("album_id", album.id)
              |> Map.put("artist_id", album.artist_id)
              |> Map.put("creator_id", user_id)
              |> Map.put("is_single", false)
              |> Map.put("duration_seconds", duration)
              |> Map.put("is_cover", is_cover)
              |> Map.put("original_track_id", orig_track_id)

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

  def create_single(attrs, user_id) do
    duration = parse_int(Map.get(attrs, "duration_seconds"))
    is_cover = parse_boolean(Map.get(attrs, "is_cover"))
    orig_track_id = parse_nullable_id(Map.get(attrs, "original_track_id"))

    attrs =
      attrs
      |> Map.put("creator_id", user_id)
      |> Map.put("is_single", true)
      |> Map.put("album_id", nil)
      |> Map.put("duration_seconds", duration)
      |> Map.put("is_cover", is_cover)
      |> Map.put("original_track_id", orig_track_id)

    %Track{}
    |> Track.changeset(attrs)
    |> Repo.insert()
  end

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

  def notify_creator(schema, item, status, comment) do
    item_name =
      case schema do
        Artist -> "Исполнитель \"#{item.name}\""
        Album -> "Альбом \"#{item.title}\""
        Track -> "Трек/Сингл \"#{item.title}\""
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
            order_by: [desc: a.inserted_at],
            preload: [
              tracks: ^from(t in Track,
                where: t.status == "approved",
                order_by: [asc: t.id],
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
            order_by: [desc: t.inserted_at],
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
end
