defmodule MusicPlatformApiWeb.StreamController do
  use MusicPlatformApiWeb, :controller
  alias MusicPlatformApi.Repo
  alias MusicPlatformApi.Music.Track

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

        conn
        |> put_resp_header("content-range", "bytes #{start_byte}-#{end_byte}/#{file_size}")
        |> put_resp_header("accept-ranges", "bytes")
        |> put_resp_header("content-type", "audio/mpeg")
        |> put_status(206)
        |> send_resp(206, data)

      _ ->
        conn
        |> put_resp_header("content-type", "audio/mpeg")
        |> put_resp_header("content-length", to_string(file_size))
        |> put_resp_header("accept-ranges", "bytes")
        |> send_file(200, path)
    end
  end
end
