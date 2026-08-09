defmodule LiveMap do
  @external_resource "./README.md"
  @moduledoc """
  #{File.read!(@external_resource)}
  """

  use Phoenix.LiveComponent
  embed_templates("live_map/*")

  alias LiveMap.Coordinate
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
     |> assign_new(:marker, fn -> [] end)}
  end

  @impl Phoenix.LiveComponent
  @spec update(Phoenix.LiveView.Socket.assigns(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{tile_layer_result: tile_layer, async_ref: ref}, socket) do
    if socket.assigns[:async_ref] == ref do
      {:ok, assign(socket, :tile_layer, tile_layer)}
    else
      {:ok, socket}
    end
  end

  def update(
        %{tile_layer_delta: delta, async_ref: ref, tile_cache_context: cache_context},
        socket
      ) do
    same_request? = socket.assigns[:async_ref] == ref
    same_cache? = socket.assigns[:tile_cache_context] == cache_context

    if same_request? or same_cache? do
      tile_layer = Tile.merge_vector_delta(socket.assigns.tile_layer, delta)
      {:ok, assign(socket, :tile_layer, tile_layer)}
    else
      {:ok, socket}
    end
  end

  def update(%{tile_layer_delta: delta, async_ref: ref}, socket) do
    if socket.assigns[:async_ref] == ref do
      tile_layer = Tile.merge_vector_delta(socket.assigns.tile_layer, delta)
      {:ok, assign(socket, :tile_layer, tile_layer)}
    else
      {:ok, socket}
    end
  end

  def update(%{tile_layer_complete: true, async_ref: ref}, socket) do
    if socket.assigns[:async_ref] == ref do
      {:ok, assign(socket, :tile_layer, Tile.complete_vector_layer(socket.assigns.tile_layer))}
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket) do
    merged_assigns =
      socket.assigns
      |> Map.merge(Map.new(assigns))
      |> Map.delete(:live_map_prepared)

    prepared_assigns = prepare_render_assigns(merged_assigns)

    {:ok, assign(socket, Map.drop(prepared_assigns, [:__changed__, :flash, :myself]))}
  end

  attr(:id, :string, required: true)
  attr(:class, :string, default: nil)
  attr(:width, :any, default: 300)
  attr(:height, :any, default: 150)
  attr(:title, :string, default: "")

  attr(:center, :any,
    default: nil,
    doc: ~s(Map center as "latitude,longitude", a tuple, or a map with :lat and :lng)
  )

  attr(:latitude, :any, default: nil, doc: "Deprecated; use center instead")
  attr(:longitude, :any, default: nil, doc: "Deprecated; use center instead")
  attr(:zoom, :any, default: 0)
  attr(:styles, :list, default: [])

  attr(:"rendering-type", :string,
    default: nil,
    doc: ~s(Rendering type enum: "raster" or "vector")
  )

  attr(:tile_source, :map, default: nil, doc: "Custom tile source and legacy rendering selector")
  attr(:tiles, :list, default: [])
  attr(:tile_layer, :map, default: %{defs: [], tiles: []})
  attr(:shape_overlays, :list, default: [])
  attr(:marker_overlays, :list, default: [])
  slot(:style)
  slot(:zoom_in)
  slot(:zoom_out)

  slot :polyline do
    attr(:id, :any)
    attr(:points, :list, required: true)
    attr(:label, :string)
    attr(:class, :any)
    attr(:style, :any)
    attr(:fill, :any)
    attr(:stroke, :any)
    attr(:"stroke-width", :any)
  end

  slot :polygon do
    attr(:id, :any)
    attr(:points, :list, required: true)
    attr(:label, :string)
    attr(:class, :any)
    attr(:style, :any)
    attr(:fill, :any)
    attr(:stroke, :any)
    attr(:"stroke-width", :any)
  end

  slot :marker do
    attr(:id, :any)
    attr(:position, :any, doc: ~s(Marker position in the same formats accepted by center))
    attr(:title, :string, doc: "Marker rollover and accessibility text")
    attr(:latitude, :any, doc: "Deprecated; use position instead")
    attr(:longitude, :any, doc: "Deprecated; use position instead")
    attr(:label, :string, doc: "Deprecated; use title instead")
  end

  @impl Phoenix.LiveComponent
  def render(assigns), do: live_map(prepare_render_assigns(assigns))

  @impl Phoenix.LiveComponent
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  # Only handles <kbd>Enter</kbd> and <kbd>Space Bar</kbd> on the zoom in button.
  # Notes that we accept both `" "` and `"Spacebar"` since older browsers send that,
  # including Firefox < 37 and Internet Explorer 9, 10, and 11.
  def handle_event("zoom_in", %{"key" => key}, socket)
      when key not in ["Enter", " ", "Spacebar"] do
    {:noreply, socket}
  end

  def handle_event("zoom_in", _params, socket) do
    zoom = socket.assigns[:zoom]

    {:noreply,
     socket
     |> assign(:zoom, zoom + 1)
     |> assign_prepared_layers()}
  end

  # Only handles <kbd>Enter</kbd> and <kbd>Space Bar</kbd> on the zoom out button.
  # Notes that we accept both `" "` and `"Spacebar"` since older browsers send that,
  # including Firefox < 37 and Internet Explorer 9, 10, and 11.
  def handle_event("zoom_out", %{"key" => key}, socket)
      when key not in ["Enter", " ", "Spacebar"] do
    {:noreply, socket}
  end

  # When no key is sent, it is a click event.
  def handle_event("zoom_out", _params, socket) do
    zoom = socket.assigns[:zoom]

    {:noreply,
     socket
     |> assign(:zoom, zoom - 1)
     |> assign_prepared_layers()}
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
      }),
      do: Tile.map(latitude, longitude, zoom, width, height)

  defp prepare_render_assigns(%{live_map_prepared: true} = assigns), do: assigns

  defp prepare_render_assigns(assigns) do
    assigns
    |> Map.new()
    |> Map.put_new(:id, "live-map")
    |> Map.put_new(:width, 300)
    |> Map.put_new(:height, 150)
    |> Map.put_new(:title, "")
    |> Map.put_new(:style, [])
    |> Map.put_new(:zoom, 0)
    |> Map.put_new(:zoom_in, [])
    |> Map.put_new(:zoom_out, [])
    |> Map.put_new(:polyline, [])
    |> Map.put_new(:polygon, [])
    |> Map.put_new(:marker, [])
    |> Map.put_new(:center, nil)
    |> Map.put_new(:latitude, nil)
    |> Map.put_new(:longitude, nil)
    |> Map.put_new(:"rendering-type", nil)
    |> Map.put_new(:tile_source, nil)
    |> assign_prepared_layers()
  end

  defp assign_prepared_layers(socket_or_assigns) do
    assigns = extract_assigns(socket_or_assigns)
    width = parse(assigns[:width], :integer)
    height = parse(assigns[:height], :integer)
    {latitude, longitude} = center(assigns)
    zoom = parse(assigns[:zoom] || 0, :integer)
    styles = assigns[:styles] || []
    tiles = Tile.map(latitude, longitude, zoom, width, height)
    css = LiveMap.Style.to_css(styles)
    {rendering_type, tile_source} = tile_source(assigns)
    tile_cache_context = {tile_source, css}

    needs_new_layer? =
      assigns[:tile_layer] == nil or
        assigns[:tiles] != tiles or
        assigns[:rendered_tile_source] != tile_source or
        assigns[:computed_css] != css

    {tile_layer, ref} =
      if needs_new_layer? do
        existing_layer = assigns[:tile_layer]

        can_reuse_layer? =
          existing_layer != nil and assigns[:rendered_tile_source] == tile_source and
            assigns[:computed_css] == css

        layer_to_diff = if can_reuse_layer?, do: existing_layer, else: %{defs: [], tiles: []}

        layer = Tile.prepare_layer(tiles, tile_source, layer_to_diff)
        sync? = assigns[:sync] || false
        new_ref = make_ref()

        layer_result =
          if layer.source.type == :mvt do
            if sync? do
              Tile.fetch_vector_layer(tiles, tile_source, css, layer_to_diff)
            else
              pid = self()
              map_id = assigns[:id] || "live-map"

              if Enum.any?(layer.tiles, &(&1.state == "loading")) do
                Task.start(fn ->
                  Tile.stream_vector_layer(tiles, tile_source, css, layer, fn delta ->
                    Phoenix.LiveView.send_update(pid, LiveMap,
                      id: map_id,
                      async_ref: new_ref,
                      tile_cache_context: tile_cache_context,
                      tile_layer_delta: delta
                    )
                  end)

                  Phoenix.LiveView.send_update(pid, LiveMap,
                    id: map_id,
                    async_ref: new_ref,
                    tile_layer_complete: true
                  )
                end)
              end

              layer
            end
          else
            layer
          end

        {Map.take(layer_result, [
           :defs,
           :definitions,
           :definition_order,
           :cached_tiles,
           :cache_order,
           :tiles
         ]), new_ref}
      else
        {assigns[:tile_layer], assigns[:async_ref]}
      end

    center_x = Tile.x(longitude, zoom) * 256.0
    center_y = Tile.y(latitude, zoom) * 256.0
    min_x = center_x - width / 2.0
    min_y = center_y - height / 2.0

    base_assigns =
      assigns
      |> Map.put(:width, width)
      |> Map.put(:height, height)
      |> Map.put(:latitude, latitude)
      |> Map.put(:longitude, longitude)
      |> Map.put(:"rendering-type", rendering_type)
      |> Map.put(:zoom, zoom)
      |> Map.put(:min_x, min_x)
      |> Map.put(:min_y, min_y)
      |> Map.put(:tile_source, tile_source)
      |> Map.put(:tiles, tiles)
      |> Map.put(:computed_css, css)
      |> Map.put(:rendered_tile_source, tile_source)
      |> Map.put(:rendered_zoom, zoom)
      |> Map.put(:tile_cache_context, tile_cache_context)
      |> Map.put(:tile_layer, tile_layer)
      |> Map.put(:async_ref, ref)
      |> Map.put(
        :shape_overlays,
        shape_overlays(
          assigns |> Map.put(:zoom, zoom) |> Map.put(:longitude, longitude),
          min_x,
          min_y
        )
      )
      |> Map.put(
        :marker_overlays,
        marker_overlays(
          assigns |> Map.put(:zoom, zoom) |> Map.put(:longitude, longitude),
          min_x,
          min_y
        )
      )
      |> Map.put(:live_map_prepared, true)

    put_assigns(socket_or_assigns, base_assigns)
  end

  defp shape_overlays(
         %{id: map_id, polyline: polylines, polygon: polygons, zoom: zoom} = assigns,
         min_x,
         min_y
       ) do
    map_longitude = parse(Map.get(assigns, :longitude, 0.0), :float)

    projected_polygons =
      polygons
      |> Enum.with_index()
      |> Enum.map(fn {polygon, index} ->
        Marker.project_shape(:polygon, polygon, map_id, zoom, min_x, min_y, index, map_longitude)
      end)

    projected_polylines =
      polylines
      |> Enum.with_index()
      |> Enum.map(fn {polyline, index} ->
        Marker.project_shape(
          :polyline,
          polyline,
          map_id,
          zoom,
          min_x,
          min_y,
          index,
          map_longitude
        )
      end)

    projected_polygons ++ projected_polylines
  end

  defp marker_overlays(%{id: map_id, marker: markers, zoom: zoom} = assigns, min_x, min_y) do
    map_longitude = parse(Map.get(assigns, :longitude, 0.0), :float)

    markers
    |> Enum.with_index()
    |> Enum.map(fn {marker, index} ->
      Marker.project(marker, map_id, zoom, min_x, min_y, index, map_longitude)
    end)
  end

  defp center(%{center: value}) when not is_nil(value) do
    Coordinate.parse_pair(value, :center)
  end

  defp center(assigns) do
    {
      Coordinate.parse_number(Map.get(assigns, :latitude) || 0.0, :center),
      Coordinate.parse_number(Map.get(assigns, :longitude) || 0.0, :center)
    }
  end

  defp tile_source(%{"rendering-type": "raster"}), do: {"raster", Tile.default_source()}

  defp tile_source(%{"rendering-type": "vector"}),
    do: {"vector", Tile.default_vector_source()}

  defp tile_source(%{"rendering-type": nil} = assigns) do
    {nil, Map.get(assigns, :tile_source) || Tile.default_source()}
  end

  defp tile_source(assigns) do
    raise ArgumentError,
          "rendering-type must be \"raster\" or \"vector\", got: " <>
            inspect(Map.get(assigns, :"rendering-type"))
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

  defp extract_assigns(%Phoenix.LiveView.Socket{assigns: assigns}), do: assigns
  defp extract_assigns(assigns) when is_map(assigns), do: assigns

  defp put_assigns(%Phoenix.LiveView.Socket{} = socket, assigns) do
    assign(socket, Map.drop(assigns, [:__changed__, :flash, :myself]))
  end

  defp put_assigns(_assigns, prepared_assigns), do: prepared_assigns

  @doc """
  Returns the viewbox that covers the tiles.

  This essentially starts from the top left tile, and ends at the bottom right tile.

  Examples:

      iex> LiveMap.viewbox([])
      "0 0 0 0"

      iex> LiveMap.viewbox([%{x: 0, y: 0}])
      "0 0 256 256"

      iex> LiveMap.viewbox([
      ...>   %{x: 0, y: 0},
      ...>   %{x: 0, y: 1},
      ...>   %{x: 1, y: 0},
      ...>   %{x: 1, y: 1}
      ...> ])
      "0 0 512 512"

  """
  @spec viewbox(list(Tile.t())) :: String.t()
  def viewbox([]), do: "0 0 0 0"

  def viewbox(tiles) do
    %{x: min_x, y: min_y} = List.first(tiles)
    %{x: max_x, y: max_y} = List.last(tiles)
    "#{min_x * 256} #{min_y * 256} #{(max_x + 1 - min_x) * 256} #{(max_y + 1 - min_y) * 256}"
  end

  @doc false
  def viewbox(latitude, longitude, zoom, width, height) do
    center_x = Tile.x(longitude, zoom) * 256.0
    center_y = Tile.y(latitude, zoom) * 256.0
    w = width
    h = height
    min_x = center_x - w / 2.0
    min_y = center_y - h / 2.0
    "#{min_x} #{min_y} #{w} #{h}"
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
