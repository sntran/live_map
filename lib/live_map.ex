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
    {:ok,
      socket
      |> assign(assigns)
      |> assign_tiles()
    }
  end

  # @callback render/1 is handled by `Phoenix.LiveView.Renderer.before_compile`
  # by looking for a ".html" file with the same name as this module.

  defp assign_tiles(socket) do
    width = parse(socket.assigns[:width], :integer)
    height = parse(socket.assigns[:height], :integer)
    latitude = parse(socket.assigns[:latitude] || 0.0, :float)
    longitude = parse(socket.assigns[:longitude] || 0.0, :float)
    zoom = parse(socket.assigns[:zoom] || 0, :integer)

    tiles = Tile.map(latitude, longitude, zoom, width, height)
    socket
    |> assign(:width, width)
    |> assign(:height, height)
    |> assign(:latitude, latitude)
    |> assign(:longitude, longitude)
    |> assign(:zoom, zoom)
    |> assign(:tiles, tiles)
  end

  defp parse(value, :integer) when is_binary(value) do
    {result, _} = Integer.parse(value)
    result
  end
  defp parse(value, :float) when is_binary(value) do
    {result, _} = Float.parse(value)
    result
  end
  defp parse(value, type), do: parse("#{value}", type)

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
