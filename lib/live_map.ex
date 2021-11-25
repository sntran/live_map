defmodule LiveMap do
  @external_resource "./README.md"
  @moduledoc """
  #{File.read!(@external_resource)}
  """

  require Logger
  alias LiveMap.Tile

  use Phoenix.LiveComponent

  @impl Phoenix.LiveComponent
  @spec mount(Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(socket) do
    {:ok,
      socket
      |> assign_new(:width, fn -> 300 end)
      |> assign_new(:height, fn -> 150 end)
      |> assign_new(:title, fn -> "" end)
    }
  end

  @impl Phoenix.LiveComponent
  @spec update(Phoenix.LiveView.Socket.assigns(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    width = assigns[:width] || socket.assigns[:width]
    height = assigns[:height] || socket.assigns[:height]
    latitude = assigns[:latitude] || socket.assigns[:latitude] || 0
    longitude = assigns[:longitude] || socket.assigns[:longitude] || 0
    zoom = assigns[:zoom] || socket.assigns[:zoom] || 0

    center = Tile.at(latitude, longitude, zoom)
    tiles = Tile.map(center, width, height)

    {:ok,
      socket
      |> assign(assigns)
      |> assign(:zoom, zoom)
      |> assign(:tiles, tiles)
    }
  end

  # @callback render/1 is handled by `Phoenix.LiveView.Renderer.before_compile`
  # by looking for a ".html" file with the same name as this module.
end
