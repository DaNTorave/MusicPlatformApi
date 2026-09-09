defmodule MusicPlatformApi.ID3 do
  import Bitwise

  def inject_tags(file_binary, tags) do
    frames = [
      build_text_frame("TIT2", Map.get(tags, :title)),
      build_text_frame("TPE1", Map.get(tags, :artist)),
      build_text_frame("TALB", Map.get(tags, :album)),
      build_text_frame("TRCK", Map.get(tags, :track)),
      build_text_frame("TYER", Map.get(tags, :year))
    ]
    |> Enum.reject(&is_nil/1)
    |> IO.iodata_to_binary()

    tag_header = build_header(byte_size(frames))
    clean_audio = strip_existing_id3(file_binary)

    tag_header <> frames <> clean_audio
  end

  defp build_header(size) do
    syncsafe_size = encode_syncsafe(size)
    <<"ID3", 3, 0, 0, syncsafe_size::binary-size(4)>>
  end

  defp build_text_frame(_id, nil), do: nil
  defp build_text_frame(_id, ""), do: nil
  defp build_text_frame(id, text) when byte_size(id) == 4 do
    str = to_string(text)
    payload = <<3>> <> str
    frame_size = byte_size(payload)
    <<id::binary-size(4), frame_size::32, 0::16, payload::binary>>
  end

  defp encode_syncsafe(size) do
    b0 = band(bsr(size, 21), 0x7F)
    b1 = band(bsr(size, 14), 0x7F)
    b2 = band(bsr(size, 7), 0x7F)
    b3 = band(size, 0x7F)
    <<b0, b1, b2, b3>>
  end

  defp strip_existing_id3(<<"ID3", _ver::16, _flags::8, b0, b1, b2, b3, rest::binary>>) do
    tag_size = bsl(band(b0, 0x7F), 21) + bsl(band(b1, 0x7F), 14) + bsl(band(b2, 0x7F), 7) + band(b3, 0x7F)
    if byte_size(rest) >= tag_size do
      <<_tag_body::binary-size(^tag_size), audio::binary>> = rest
      audio
    else
      rest
    end
  end

  defp strip_existing_id3(binary), do: binary
end
