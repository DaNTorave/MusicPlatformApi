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

alias MusicPlatformApi.{Repo, UserAdmin, UserOwner}


Repo.insert!(%UserAdmin{
  login: "admin",
  email: "admin@gmail.com",
  nickname: "admin",
  role: "admin",
  password_hash: Pbkdf2.hash_pwd_salt("admin")
})

Repo.insert!(%UserOwner{
  login: "owner",
  email: "owner@gmail.com",
  nickname: "owner",
  role: "owner",
  password_hash: Pbkdf2.hash_pwd_salt("owner")
})
