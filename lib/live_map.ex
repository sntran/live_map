defmodule LiveMap do
  @external_resource "./README.md"
  @moduledoc """
  #{File.read!(@external_resource)}
  """

  require Logger
  alias LiveMap.Tile

  @doc deletegate_to: {Tile, :map, 5}
  defdelegate tiles(latitude, longitude, zoom, width, height), to: Tile, as: :map
  @doc deletegate_to: {Tile, :map, 6}
  defdelegate tiles(latitude, longitude, zoom, width, height, mapper), to: Tile, as: :map

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

  @doc """
  Returns the viewbox that covers the tiles.

  This essentially starts from the top left tile, and ends at the bottom right tile.

  Examples:

      iex> LiveMap.viewbox([])
      "0 0 0 0"

      iex> LiveMap.viewbox([%{x: 0, y: 0}])
      "0 0 1 1"

      iex> LiveMap.viewbox([
      ...>   %{x: 0, y: 0},
      ...>   %{x: 0, y: 1},
      ...>   %{x: 1, y: 0},
      ...>   %{x: 1, y: 1}
      ...> ])
      "0 0 2 2"

  """
  @spec viewbox(list(Tile.t())) :: String.t()
  def viewbox([]), do: "0 0 0 0"
  def viewbox(tiles) do
    %{x: min_x, y: min_y} = List.first(tiles)
    %{x: max_x, y: max_y} = List.last(tiles)
    "#{min_x} #{min_y} #{max_x + 1 - min_x} #{max_y + 1 - min_y}"
  end
end
