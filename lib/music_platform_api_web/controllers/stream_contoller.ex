defmodule MusicPlatformApiWeb.StreamController do
  use MusicPlatformApiWeb, :controller
  alias MusicPlatformApi.Repo
  alias MusicPlatformApi.Music.Track
  alias MusicPlatformApi.ID3

  def stream(conn, %{"id" => id}) do
    track = Repo.get!(Track, id)

    if File.exists?(track.file_path) do
      Task.start(fn ->
        Ecto.Adapters.SQL.query(Repo, "UPDATE tracks SET plays_count = plays_count + 1 WHERE id = $1", [track.id])
        Ecto.Adapters.SQL.query(Repo, "UPDATE artists SET plays_count = plays_count + 1 WHERE id = $1", [track.artist_id])
      end)

      file_size = File.stat!(track.file_path).size
      send_audio_stream(conn, track.file_path, file_size)
    else
      conn |> put_status(:not_found) |> json(%{error: "Файл не найден на диске"})
    end
  end

  # Отправляет аудиофайл с учетом HTTP-заголовка Range для перемотки в плеере.
  defp send_audio_stream(conn, path, file_size) do
    case get_req_header(conn, "range") do
      ["bytes=" <> range_spec] ->
        [start_str, end_str] =
          case String.split(range_spec, "-") do
            [s, ""] -> [s, to_string(file_size - 1)]
            [s, e] -> [s, e]
          end

        start_byte = String.to_integer(start_str)
        end_byte = min(String.to_integer(end_str), file_size - 1)
        length = end_byte - start_byte + 1

        {:ok, file} = :file.open(path, [:read, :binary])
        {:ok, data} = :file.pread(file, start_byte, length)
        :file.close(file)

        # Возврат контента по частям (Статус 206)
        conn
        |> put_resp_header("content-range", "bytes #{start_byte}-#{end_byte}/#{file_size}")
        |> put_resp_header("accept-ranges", "bytes")
        |> put_resp_header("content-type", "audio/mpeg")
        |> put_status(206)
        |> send_resp(206, data)

      _ ->
        # Возврат полностью
        conn
        |> put_resp_header("content-type", "audio/mpeg")
        |> put_resp_header("content-length", to_string(file_size))
        |> put_resp_header("accept-ranges", "bytes")
        |> send_file(200, path)
    end
  end

  def download(conn, %{"id" => id}) do
    track =
      Track
      |> Repo.get!(id)
      |> Repo.preload([:artist, :album])

    if File.exists?(track.file_path) do
      # Подготовка метаданных
      artist_name = if track.artist, do: track.artist.name, else: "Неизвестный исполнитель"
      track_title = track.title || "Без названия"
      album_title = if track.album, do: track.album.title, else: ""

      pos_str = to_string(track.position || 1)
      year_str = if track.release_year, do: to_string(track.release_year), else: ""

      # Поиск и чтение файла обложки с диска
      cover_bytes = load_track_cover(track)

      original_bytes = File.read!(track.file_path)

      # Вставка метаданных и обложки в MP3
      tagged_audio =
        ID3.inject_tags(original_bytes, %{
          title: track_title,
          artist: artist_name,
          album: album_title,
          track: pos_str,
          year: year_str,
          cover: cover_bytes
        })

      # Форматирование имени файла
      clean_name = String.replace("#{artist_name} — #{track_title}", ~r/[\\\/:\*\?"<>\|]/u, "")
      encoded_filename = URI.encode("#{clean_name}.mp3")

      conn
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"#{encoded_filename}\"; filename*=UTF-8''#{encoded_filename}"
      )
      |> put_resp_header("content-type", "audio/mpeg")
      |> put_resp_header("content-length", to_string(byte_size(tagged_audio)))
      |> send_resp(200, tagged_audio)
    else
      conn |> put_status(:not_found) |> json(%{error: "Файл не найден"})
    end
  end

  # Загрузка бинарных данных обложки (приоритет: трек -> альбом -> артист)
  defp load_track_cover(track) do
    cover_url =
      cond do
        is_binary(track.cover) and String.trim(track.cover) != "" ->
          track.cover

        is_map(track.album) and is_binary(track.album.cover) and String.trim(track.album.cover) != "" ->
          track.album.cover

        is_map(track.artist) and is_binary(track.artist.avatar) and String.trim(track.artist.avatar) != "" ->
          track.artist.avatar

        true ->
          nil
      end

    case resolve_disk_path(cover_url) do
      {:ok, path} ->
        case File.read(path) do
          {:ok, binary} -> binary
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Поиск физического файла на диске по относительному или статическому URL
  defp resolve_disk_path(nil), do: :error
  defp resolve_disk_path(""), do: :error
  defp resolve_disk_path(url_or_path) do
    clean_path = String.replace_leading(url_or_path, "/", "")

    candidates = [
      url_or_path,
      clean_path,
      Path.join("priv/static", clean_path),
      Path.expand(Path.join("priv/static", clean_path)),
      try do
        Application.app_dir(:music_platform_api, Path.join("priv/static", clean_path))
      rescue
        _ -> nil
      end
    ]
    |> Enum.reject(&is_nil/1)

    case Enum.find(candidates, &File.exists?/1) do
      nil -> :error
      path -> {:ok, path}
    end
  end
end
