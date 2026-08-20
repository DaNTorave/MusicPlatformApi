# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     MusicPlatformApi.Repo.insert!(%MusicPlatformApi.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias MusicPlatformApi.{Repo, User}


Repo.insert!(%User{
  login: "admin",
  email: "admin@gmail.com",
  nickname: "admin",
  role: "admin",
  password_hash: Pbkdf2.hash_pwd_salt("admin")
})
