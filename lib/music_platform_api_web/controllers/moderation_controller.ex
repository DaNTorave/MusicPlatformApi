defmodule MusicPlatformApiWeb.ModerationController do
  use MusicPlatformApiWeb, :controller
  import Ecto.Query
  alias MusicPlatformApi.{Auth, Repo, Music}
  alias MusicPlatformApi.Music.{Artist, Album, Track}

  def pending_list(conn, _params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) and user.role in ["admin", "moderator"] <- Auth.get_user_from_token(token) do

      format_creator = fn creator ->
        if creator do
          %{id: creator.id, login: creator.login, nickname: creator.nickname}
        else
          nil
        end
      end

      format_artist = fn artist ->
        if artist do
          %{id: artist.id, name: artist.name}
        else
          nil
        end
      end

      artists =
        Repo.all(from a in Artist, where: a.status == "pending", preload: [:creator])
        |> Enum.map(fn a ->
          a
          |> Map.from_struct()
          |> Map.drop([:__meta__, :creator, :albums, :tracks, :collab_tracks])
          |> Map.put(:type, "artist")
          |> Map.put(:creator_info, format_creator.(a.creator))
        end)

      albums =
        Repo.all(
          from a in Album,
            where: a.status == "pending",
            preload: [:creator, :artist, tracks: ^from(t in Track, order_by: [asc: t.id], preload: [:collaborators])]
        )
        |> Enum.map(fn a ->
          formatted_tracks = Enum.map(a.tracks || [], fn t ->
            %{
              id: t.id,
              title: t.title,
              audio_uuid: t.audio_uuid,
              duration_seconds: t.duration_seconds,
              is_single: t.is_single,
              status: t.status,
              collaborators: Enum.map(t.collaborators || [], &%{id: &1.id, name: &1.name})
            }
          end)

          a
          |> Map.from_struct()
          |> Map.drop([:__meta__, :creator, :artist, :tracks])
          |> Map.put(:type, "album")
          |> Map.put(:tracks, formatted_tracks)
          |> Map.put(:creator_info, format_creator.(a.creator))
          |> Map.put(:artist_info, format_artist.(a.artist))
        end)

      tracks =
        Repo.all(
          from t in Track,
            where: t.status == "pending" and t.is_single == true,
            preload: [:creator, :artist, :collaborators]
        )
        |> Enum.map(fn t ->
          t
          |> Map.from_struct()
          |> Map.drop([:__meta__, :creator, :artist, :album, :collaborators])
          |> Map.put(:type, "track")
          |> Map.put(:creator_info, format_creator.(t.creator))
          |> Map.put(:artist_info, format_artist.(t.artist))
          |> Map.put(:collaborators, Enum.map(t.collaborators || [], &%{id: &1.id, name: &1.name}))
        end)

      json(conn, %{items: artists ++ albums ++ tracks})
    else
      _ -> conn |> put_status(:forbidden) |> json(%{error: "Доступ запрещен"})
    end
  end

  def make_decision(conn, %{"schema" => schema_str, "id" => id, "status" => status} = params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) and user.role in ["admin", "moderator"] <- Auth.get_user_from_token(token) do

      schema =
        case String.downcase(to_string(schema_str)) do
          "artist" -> Artist
          "album" -> Album
          "track" -> Track
          "single" -> Track
          _ -> nil
        end

      if schema do
        comment = Map.get(params, "comment", "")

        case Music.moderate_item(schema, id, status, comment) do
          {:ok, item} ->
            json(conn, %{success: true, item: item})

          {:error, %Ecto.Changeset{} = changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            conn |> put_status(:bad_request) |> json(%{error: "Ошибка валидации", details: errors})

          {:error, reason} ->
            conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
        end
      else
        conn |> put_status(:bad_request) |> json(%{error: "Неизвестный тип сущности: #{schema_str}"})
      end
    else
      _ -> conn |> put_status(:forbidden) |> json(%{error: "Доступ запрещен"})
    end
  end

  def make_decision(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Отсутствуют обязательные параметры (schema, id, status)"})
  end

  def approve_with_edit(conn, %{"schema" => schema_str} = params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         user when not is_nil(user) and user.role in ["admin", "moderator"] <- Auth.get_user_from_token(token) do

      schema = case String.downcase(to_string(schema_str)) do
        "artist" -> Artist
        "album" -> Album
        "track" -> Track
        "single" -> Track
        _ -> nil
      end

      if is_nil(schema) do
        return_error(conn, :bad_request, "Неизвестный тип сущности: #{schema_str}")
      else
        item_id = if is_binary(params["id"]), do: String.to_integer(params["id"]), else: params["id"]
        item = Repo.get!(schema, item_id)

        update_attrs = %{status: "approved", moderation_comment: "Одобрено модератором"}

        update_attrs = if Map.has_key?(params, "title") and params["title"] != "" do
          if schema == Artist do
            Map.put(update_attrs, :name, params["title"])
          else
            Map.put(update_attrs, :title, params["title"])
          end
        else
          update_attrs
        end

        update_attrs = case Map.get(params, "cover") do
          %Plug.Upload{} = upload ->
            {:ok, url, _path} = Music.save_upload(upload, "covers")
            Map.put(update_attrs, :cover, url)
          _ ->
            update_attrs
        end

        update_attrs = case {schema, Map.get(params, "audio")} do
          {Track, %Plug.Upload{} = upload} ->
            {:ok, _url, path} = Music.save_upload(upload, "tracks")
            uuid = Path.basename(path, Path.extname(path))
            update_attrs
            |> Map.put(:audio_uuid, uuid)
            |> Map.put(:file_path, path)
          _ ->
            update_attrs
        end

        Repo.transaction(fn ->
          if schema == Album do
            tracks_params = Map.get(params, "tracks", %{})

            submitted_track_ids =
              tracks_params
              |> Enum.map(fn {_k, v} -> v["id"] end)
              |> Enum.reject(&is_nil/1)
              |> Enum.map(fn id -> if is_binary(id), do: String.to_integer(id), else: id end)

            from(t in Track, where: t.album_id == ^item.id and t.id not in ^submitted_track_ids)
            |> Repo.delete_all()

            Enum.each(tracks_params, fn {_idx, t_param} ->
              track_id = t_param["id"]

              if track_id && track_id != "" do
                track = Repo.get(Track, track_id)

                if track do
                  t_attrs = %{status: "approved", moderation_comment: "Одобрено модератором"}
                  t_attrs = if t_param["title"], do: Map.put(t_attrs, :title, t_param["title"]), else: t_attrs

                  t_attrs = case t_param["audio"] do
                    %Plug.Upload{} = upload ->
                      {:ok, _url, path} = Music.save_upload(upload, "tracks")
                      uuid = Path.basename(path, Path.extname(path))
                      t_attrs
                      |> Map.put(:audio_uuid, uuid)
                      |> Map.put(:file_path, path)
                    _ ->
                      t_attrs
                  end

                  track
                  |> Track.moderation_changeset(t_attrs)
                  |> Ecto.Changeset.change(Map.drop(t_attrs, [:status, :moderation_comment]))
                  |> Repo.update!()
                end
              else
                if t_param["audio"] do
                  %Plug.Upload{} = upload = t_param["audio"]
                  {:ok, _url, path} = Music.save_upload(upload, "tracks")
                  uuid = Path.basename(path, Path.extname(path))

                  %Track{}
                  |> Track.changeset(%{
                    "title" => t_param["title"] || "Без названия",
                    "audio_uuid" => uuid,
                    "file_path" => path,
                    "album_id" => item.id,
                    "artist_id" => item.artist_id,
                    "creator_id" => item.creator_id,
                    "is_single" => false
                  })
                  |> Track.moderation_changeset(%{status: "approved", moderation_comment: "Одобрено модератором"})
                  |> Repo.insert!()
                end
              end
            end)

            from(t in Track, where: t.album_id == ^item.id)
            |> Repo.update_all(set: [status: "approved", moderation_comment: "Одобрено модератором"])
          end

          raw_collabs = Map.get(params, "collaborator_ids") || Map.get(params, "collaborator_ids[]")
          if raw_collabs do
            collab_ids =
              case raw_collabs do
                ids when is_list(ids) -> ids
                id when is_binary(id) or is_integer(id) -> [id]
                _ -> []
              end
              |> Enum.reject(&(&1 == "" or is_nil(&1)))

            artists = Repo.all(from a in Artist, where: a.id in ^collab_ids)

            if schema == Track do
              item
              |> Repo.preload(:collaborators)
              |> Ecto.Changeset.change()
              |> Ecto.Changeset.put_assoc(:collaborators, artists)
              |> Repo.update!()
            end

            if schema == Album do
              album_tracks = Repo.all(from t in Track, where: t.album_id == ^item.id, preload: [:collaborators])
              Enum.each(album_tracks, fn trk ->
                trk
                |> Ecto.Changeset.change()
                |> Ecto.Changeset.put_assoc(:collaborators, artists)
                |> Repo.update!()
              end)
            end
          end

          changeset =
            item
            |> schema.moderation_changeset(%{status: "approved", moderation_comment: "Одобрено модератором"})
            |> Ecto.Changeset.change(Map.drop(update_attrs, [:status, :moderation_comment]))

          case Repo.update(changeset) do
            {:ok, updated_item} ->
              refreshed_item = Repo.get!(schema, updated_item.id)
              Music.notify_creator(schema, refreshed_item, "approved", "Одобрено модератором")
              refreshed_item

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
        |> case do
          {:ok, final_item} ->
            json(conn, %{success: true, item: final_item})

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{
              error: "Ошибка валидации",
              details: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            })

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: inspect(reason)})
        end
      end
    else
      _ -> conn |> put_status(:forbidden) |> json(%{error: "Доступ запрещен"})
    end
  end

  defp return_error(conn, status, error_message) do
    conn
    |> put_status(status)
    |> json(%{success: false, error: error_message})
  end
end
