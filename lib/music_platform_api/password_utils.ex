defmodule MusicPlatformApi.PasswordUtils do
  def strong_password?(password) do
    String.length(password) >= 8 and
    String.match?(password, ~r/[a-z]/) and
    String.match?(password, ~r/[A-Z]/) and
    String.match?(password, ~r/[0-9]/) and
    String.match?(password, ~r/[^a-zA-Z0-9]/)
  end

  def generate_temporary_password(length \\ 12) do
    chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-="
    Enum.reduce(1..length, "", fn _, acc ->
      acc <> String.at(chars, :rand.uniform(String.length(chars)) - 1)
    end)
  end
end
