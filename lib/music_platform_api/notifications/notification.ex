defmodule MusicPlatformApi.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :title, :message, :type, :is_read, :entity_type, :entity_id, :user_id, :inserted_at, :updated_at]}
  schema "notifications" do
    field :title, :string
    field :message, :string
    field :type, :string, default: "info"
    field :is_read, :boolean, default: false
    field :entity_type, :string
    field :entity_id, :integer

    belongs_to :user, MusicPlatformApi.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:title, :message, :type, :is_read, :entity_type, :entity_id, :user_id])
    |> validate_required([:title, :message, :user_id])
  end
end
