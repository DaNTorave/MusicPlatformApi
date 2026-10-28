defmodule MusicPlatformApi.ID3 do
  import Bitwise

  # Внедрение ID3v2.3 тегов и обложки в бинарные данные MP3
  def inject_tags(file_binary, tags) do
    cover_data = Map.get(tags, :cover) || Map.get(tags, :image)
    cover_mime = Map.get(tags, :cover_mime)

    frames =
      [
        build_text_frame("TIT2", Map.get(tags, :title)),
        build_text_frame("TPE1", Map.get(tags, :artist)),
        build_text_frame("TALB", Map.get(tags, :album)),
        build_text_frame("TRCK", Map.get(tags, :track)),
        build_text_frame("TYER", Map.get(tags, :year)),
        build_picture_frame(cover_data, cover_mime)
      ]
      |> Enum.reject(&is_nil/1)
      |> IO.iodata_to_binary()

    # Размер в общем заголовке ID3v2 считается только для фреймов (без 10 байт самого заголовка ID3)
    tag_header = build_header(byte_size(frames))
    clean_audio = strip_existing_id3(file_binary)

    tag_header <> frames <> clean_audio
  end

  # Заголовок ID3v2.3: "ID3", major ver 3, revision 0, flags 0, 4 байта syncsafe
  defp build_header(size) do
    syncsafe_size = encode_syncsafe(size)
    <<"ID3", 3, 0, 0, syncsafe_size::binary-size(4)>>
  end

  # Текстовые фреймы: кодировка UTF-16LE с BOM (0xFF, 0xFE) без завершающих нулей в конце
  defp build_text_frame(_id, nil), do: nil
  defp build_text_frame(_id, ""), do: nil
  defp build_text_frame(id, text) when byte_size(id) == 4 do
    str = to_string(text)
    utf16_le = :unicode.characters_to_binary(str, :utf8, {:utf16, :little})

    # Байт 1 = UTF-16 с BOM (<<0xFF, 0xFE>> для Little Endian)
    payload = <<1, 0xFF, 0xFE>> <> utf16_le
    frame_size = byte_size(payload)

    # Заголовок фрейма: ID (4 байта) + размер данных (4 байта big-endian) + флаги (2 байта 0x0000)
    <<id::binary-size(4), frame_size::32, 0::16, payload::binary>>
  end

  # Фрейм APIC
  defp build_picture_frame(nil, _mime), do: nil
  defp build_picture_frame("", _mime), do: nil
  defp build_picture_frame(image_bytes, mime) when is_binary(image_bytes) and byte_size(image_bytes) > 0 do
    # Проверяем реальный формат картинки по сигнатуре байтов
    {real_mime, valid_bytes} = sanitize_image(image_bytes, mime)

    case valid_bytes do
      nil ->
        nil

      bytes ->
        # Структура payload фрейма APIC (ID3v2.3):
        # 1 байт: $00 (кодировка описания — ISO-8859-1)
        # N байт: MIME-тип в ASCII
        # 1 байт: $00 (нулевой терминатор для MIME)
        # 1 байт: $03 (тип обложки: Front cover)
        # 1 байт: $00 (пустое описание, завершенное нулевым байтом)
        # M байт: бинарные данные картинки
        payload = <<0>> <> real_mime <> <<0, 3, 0>> <> bytes
        frame_size = byte_size(payload)

        <<"APIC", frame_size::32, 0::16, payload::binary>>
    end
  end

  # Windows не поддерживает WebP внутри MP3 тегов. Проверяем сигнатуру и отсекаем неподдерживаемое.
  defp sanitize_image(<<0xFF, 0xD8, _rest::binary>> = bytes, _mime), do: {"image/jpeg", bytes}
  defp sanitize_image(<<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = bytes, _mime), do: {"image/png", bytes}
  defp sanitize_image(<<"RIFF", _::binary-size(4), "WEBP", _rest::binary>>, _mime) do
    # Windows Explorer / WMP крашатся на WebP в APIC. Если обложка в webp, пропускаем ее
    # или используем fallback jpeg в контроллере
    {nil, nil}
  end
  defp sanitize_image(bytes, mime) when mime in ["image/jpeg", "image/png"], do: {mime, bytes}
  defp sanitize_image(bytes, _mime), do: {"image/jpeg", bytes}

  # Кодирование размера общего заголовка ID3v2 (Syncsafe Integer: 7 бит на байт)
  defp encode_syncsafe(size) do
    b0 = band(bsr(size, 21), 0x7F)
    b1 = band(bsr(size, 14), 0x7F)
    b2 = band(bsr(size, 7), 0x7F)
    b3 = band(size, 0x7F)
    <<b0, b1, b2, b3>>
  end

  # Удаление старых тегов ID3v2 и ID3v1
  defp strip_existing_id3(<<"ID3", _ver::16, _flags::8, b0, b1, b2, b3, rest::binary>>) do
    tag_size = bsl(band(b0, 0x7F), 21) + bsl(band(b1, 0x7F), 14) + bsl(band(b2, 0x7F), 7) + band(b3, 0x7F)
    if byte_size(rest) >= tag_size do
      <<_tag_body::binary-size(^tag_size), audio::binary>> = rest
      strip_id3v1(audio)
    else
      strip_id3v1(rest)
    end
  end
  defp strip_existing_id3(binary), do: strip_id3v1(binary)

  # Срезка ID3v1 в конце файла (последние 128 байт, если начинаются на "TAG")
  defp strip_id3v1(binary) when byte_size(binary) > 128 do
    audio_size = byte_size(binary) - 128
    case binary do
      <<audio::binary-size(audio_size), "TAG", _rest::binary-size(125)>> -> audio
      _ -> binary
    end
  end
  defp strip_id3v1(binary), do: binary
end
