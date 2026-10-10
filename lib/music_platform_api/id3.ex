defmodule MusicPlatformApi.ID3 do
  import Bitwise

  # Внедрение ID3v2.3 тегов и обложки в бинарные данные MP3
  def inject_tags(file_binary, tags) do
    cover_data = Map.get(tags, :cover) || Map.get(tags, :image)

    frames = [
      build_text_frame("TIT2", Map.get(tags, :title)),
      build_text_frame("TPE1", Map.get(tags, :artist)),
      build_text_frame("TALB", Map.get(tags, :album)),
      build_text_frame("TRCK", Map.get(tags, :track)),
      build_text_frame("TYER", Map.get(tags, :year)),
      build_picture_frame(cover_data, Map.get(tags, :cover_mime))
    ]
    |> Enum.reject(&is_nil/1)
    |> IO.iodata_to_binary()

    tag_header = build_header(byte_size(frames))
    clean_audio = strip_existing_id3(file_binary)

    tag_header <> frames <> clean_audio
  end

  # Заголовок ID3v2.3 тега
  defp build_header(size) do
    syncsafe_size = encode_syncsafe(size)
    <<"ID3", 3, 0, 0, syncsafe_size::binary-size(4)>>
  end

  # Построение текстового фрейма (UTF-8)
  defp build_text_frame(_id, nil), do: nil
  defp build_text_frame(_id, ""), do: nil
  defp build_text_frame(id, text) when byte_size(id) == 4 do
    str = to_string(text)
    payload = <<3>> <> str
    frame_size = byte_size(payload)
    <<id::binary-size(4), frame_size::32, 0::16, payload::binary>>
  end

  # Построение фрейма APIC (Attached Picture) для обложки
  defp build_picture_frame(nil, _mime), do: nil
  defp build_picture_frame("", _mime), do: nil
  defp build_picture_frame(image_bytes, mime) when is_binary(image_bytes) and byte_size(image_bytes) > 0 do
    mime_type = mime || detect_image_mime(image_bytes)

    # Структура APIC в стандарте ID3v2.3:
    # 1 байт  : Кодировка текста ($00 = ISO-8859-1)
    # n байт  : MIME-тип ("image/jpeg" или "image/png")
    # 1 байт  : $00 (нуль-терминатор MIME-типа)
    # 1 байт  : $03 (тип обложки: Front Cover / лицевая обложка)
    # 1 байт  : $00 (пустое описание с нуль-терминатором)
    # m байт  : Сырые бинарные данные изображения
    payload = <<0>> <> mime_type <> <<0, 3, 0>> <> image_bytes
    frame_size = byte_size(payload)

    <<"APIC", frame_size::32, 0::16, payload::binary>>
  end

  # Определение формата изображения по сигнатуре (магическим байтам)
  defp detect_image_mime(<<0xFF, 0xD8, _rest::binary>>), do: "image/jpeg"
  defp detect_image_mime(<<0x89, 0x50, 0x4E, 0x47, _rest::binary>>), do: "image/png"
  defp detect_image_mime(<<"GIF8", _rest::binary>>), do: "image/gif"
  defp detect_image_mime(<<"RIFF", _::binary-size(4), "WEBP", _rest::binary>>), do: "image/webp"
  defp detect_image_mime(_), do: "image/jpeg"

  # Кодирование размера в 28-битный syncsafe-целочисленный формат
  defp encode_syncsafe(size) do
    b0 = band(bsr(size, 21), 0x7F)
    b1 = band(bsr(size, 14), 0x7F)
    b2 = band(bsr(size, 7), 0x7F)
    b3 = band(size, 0x7F)
    <<b0, b1, b2, b3>>
  end

  # Удаление старого ID3-тега из исходного файла
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
