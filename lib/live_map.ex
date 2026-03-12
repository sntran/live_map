defmodule LiveMap do
  @external_resource "./README.md"
  @moduledoc """
  #{File.read!(@external_resource)}
  """

  use Phoenix.LiveComponent
  embed_templates "live_map/*"

  alias LiveMap.Marker
  alias LiveMap.Tile

  @doc deletegate_to: {Tile, :map, 5}
  defdelegate tiles(latitude, longitude, zoom, width, height), to: Tile, as: :map

  @impl Phoenix.LiveComponent
  @spec mount(Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(socket) do
    {:ok,
      socket
      |> assign_new(:width, fn -> 300 end)
      |> assign_new(:height, fn -> 150 end)
      |> assign_new(:title, fn -> "" end)
      |> assign_new(:style, fn -> [] end)
      |> assign_new(:zoom, fn -> 0 end)
      |> assign_new(:zoom_in, fn -> [] end)
      |> assign_new(:zoom_out, fn -> [] end)
      |> assign_new(:polyline, fn -> [] end)
      |> assign_new(:polygon, fn -> [] end)
      |> assign_new(:marker, fn -> [] end)
    }
  end

  @impl Phoenix.LiveComponent
  @spec update(Phoenix.LiveView.Socket.assigns(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    # Merges all given assigns to `live_component/1` to the socket first.
    socket = assign(socket, assigns)
    # Then parses the assigns of interest.
    assigns = socket.assigns
    width = parse(assigns[:width], :integer)
    height = parse(assigns[:height], :integer)
    latitude = parse(assigns[:latitude] || 0.0, :float)
    longitude = parse(assigns[:longitude] || 0.0, :float)
    zoom = parse(assigns[:zoom] || 0, :integer)

    {:ok,
      socket
      # Reassign the actual assign values back to the socket.
      |> assign(:width, width)
      |> assign(:height, height)
      |> assign(:latitude, latitude)
      |> assign(:longitude, longitude)
      |> assign(:zoom, zoom)
      |> assign_tiles()
      |> assign_shape_overlays()
      |> assign_marker_overlays()
    }
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :width, :any, default: 300
  attr :height, :any, default: 150
  attr :title, :string, default: ""
  attr :latitude, :any, default: 0.0
  attr :longitude, :any, default: 0.0
  attr :zoom, :any, default: 0
  attr :tiles, :list, default: []
  attr :shape_overlays, :list, default: []
  attr :marker_overlays, :list, default: []
  slot :style
  slot :zoom_in
  slot :zoom_out
  slot :polyline do
    attr :id, :any
    attr :points, :list, required: true
    attr :label, :string
  end
  slot :polygon do
    attr :id, :any
    attr :points, :list, required: true
    attr :label, :string
  end
  slot :marker do
    attr :id, :any
    attr :latitude, :any, required: true
    attr :longitude, :any, required: true
    attr :label, :string, required: true
  end

  @impl Phoenix.LiveComponent
  def render(assigns), do: live_map(assigns)

  @impl Phoenix.LiveComponent
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  # Only handles <kbd>Enter</kbd> and <kbd>Space Bar</kbd> on the zoom in button.
  # Notes that we accept both `" "` and `"Spacebar"` since older browsers send that,
  # including Firefox < 37 and Internet Explorer 9, 10, and 11.
  def handle_event("zoom_in", %{"key" => key}, socket) when key not in ["Enter", " ", "Spacebar"] do
    {:noreply, socket}
  end
  # When no key is sent, it is a click event.
  def handle_event("zoom_in", _params, socket) do
    zoom = socket.assigns[:zoom]
    {:noreply,
     socket
     |> assign(:zoom, zoom + 1)
     |> assign_tiles()
     |> assign_shape_overlays()
     |> assign_marker_overlays()
    }
  end

  # Only handles <kbd>Enter</kbd> and <kbd>Space Bar</kbd> on the zoom out button.
  # Notes that we accept both `" "` and `"Spacebar"` since older browsers send that,
  # including Firefox < 37 and Internet Explorer 9, 10, and 11.
  def handle_event("zoom_out", %{"key" => key}, socket) when key not in ["Enter", " ", "Spacebar"] do
    {:noreply, socket}
  end
  # When no key is sent, it is a click event.
  def handle_event("zoom_out", _params, socket) do
    zoom = socket.assigns[:zoom]
    {:noreply,
     socket
      |> assign(:zoom, zoom - 1)
      |> assign_tiles()
      |> assign_shape_overlays()
      |> assign_marker_overlays()
    }
  end

  @doc """
  Generates tiles from data map. Delegates to `tiles/5`
  """
  def tiles(%{
    latitude: latitude,
    longitude: longitude,
    zoom: zoom,
    width: width,
    height: height
  }), do: Tile.map(latitude, longitude, zoom, width, height)

  defp assign_tiles(socket) do
    assign(socket, :tiles, tiles(socket.assigns))
  end

  defp assign_shape_overlays(socket) do
    assign(socket, :shape_overlays, shape_overlays(socket.assigns))
  end

  defp assign_marker_overlays(socket) do
    assign(socket, :marker_overlays, marker_overlays(socket.assigns))
  end

  defp shape_overlays(%{id: map_id, polyline: polylines, polygon: polygons, zoom: zoom}) do
    projected_polygons =
      polygons
      |> Enum.with_index()
      |> Enum.map(fn {polygon, index} ->
        Marker.project_shape(:polygon, polygon, map_id, zoom, index)
      end)

    projected_polylines =
      polylines
      |> Enum.with_index()
      |> Enum.map(fn {polyline, index} ->
        Marker.project_shape(:polyline, polyline, map_id, zoom, index)
      end)

    projected_polygons ++ projected_polylines
  end

  defp marker_overlays(%{id: map_id, marker: markers, zoom: zoom}) do
    markers
    |> Enum.with_index()
    |> Enum.map(fn {marker, index} ->
      Marker.project(marker, map_id, zoom, index)
    end)
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

  defp slot_content_present?(nil), do: false

  defp slot_content_present?(slot_content) do
    slot_content
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> String.trim()
    |> Kernel.!=("")
  end
end
