# live_earthquakes.exs — Global Earthquakes & Tectonic Plates
#
# A single-file LiveView that visualizes tectonic plates (polygons),
# plate boundaries (polylines), and recent M4.5+ earthquakes (markers).
# It also includes a toggle to demonstrate the difference between
# raster (OSM default) and vector (Shortbread) tile maps.
#
# Run:    elixir examples/live_earthquakes.exs
# Open:   http://localhost:4000/?zoom=3&center=0,0&rendering-type=vector

Mix.install([
  {:phoenix_playground, "~> 0.1.8"},
  {:req, "~> 0.6"},
  {:jason, "~> 1.4"},
  {:live_map, path: Path.expand("..", __DIR__)}
])

# Vector tile fetches need an identifying User-Agent.
Application.put_env(
  :live_map,
  :tile_user_agent,
  "LiveMapEarthquakesDemo/0.1 (https://github.com/sntran/live_map)"
)

defmodule LiveEarthquakes do
  use Phoenix.LiveView

  @default_zoom 3
  @min_zoom 0
  @max_zoom 14
  @min_latitude -85.0511
  @max_latitude 85.0511
  @min_longitude -180.0
  @max_longitude 180.0

  def mount(_params, _session, socket) do
    if connected?(socket) do
      send(self(), :load_data)
    end

    {:ok,
     assign(socket,
       page_title: "Global Earthquakes & Tectonic Plates",
       loading?: true,
       error: nil,
       rendering_type: "vector",
       zoom: @default_zoom,
       latitude: 0,
       longitude: 0,
       plates: [],
       boundaries: [],
       earthquakes: []
     )}
  end

  def handle_params(params, _uri, socket) do
    {latitude, longitude} =
      center_param(
        params["center"],
        {socket.assigns.latitude, socket.assigns.longitude}
      )

    {:noreply,
     assign(socket,
       zoom: zoom_param(params["zoom"], socket.assigns.zoom),
       latitude: latitude,
       longitude: longitude,
       rendering_type:
         rendering_type_param(params["rendering-type"], socket.assigns.rendering_type)
     )}
  end

  def handle_info(:load_data, socket) do
    pid = self()

    Task.start(fn ->
      try do
        decode = fn body -> if is_binary(body), do: Jason.decode!(body), else: body end

        plates_req =
          Req.get!(
            "https://raw.githubusercontent.com/fraxen/tectonicplates/master/GeoJSON/PB2002_plates.json"
          ).body
          |> decode.()

        boundaries_req =
          Req.get!(
            "https://raw.githubusercontent.com/fraxen/tectonicplates/master/GeoJSON/PB2002_boundaries.json"
          ).body
          |> decode.()

        earthquakes_req =
          Req.get!("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_month.geojson").body
          |> decode.()

        send(pid, {:data_loaded, plates_req, boundaries_req, earthquakes_req})
      rescue
        e ->
          IO.puts("Failed to load data: #{inspect(e)}")
          send(pid, {:data_error, "Failed to load geospatial datasets."})
      end
    end)

    {:noreply, socket}
  end

  def handle_info({:data_loaded, plates, boundaries, earthquakes}, socket) do
    plates_data = extract_polygons(plates)
    boundaries_data = extract_polylines(boundaries)
    earthquakes_data = extract_markers(earthquakes)

    {:noreply,
     assign(socket,
       loading?: false,
       plates: plates_data,
       boundaries: boundaries_data,
       earthquakes: earthquakes_data
     )}
  end

  def handle_info({:data_error, msg}, socket) do
    {:noreply, assign(socket, loading?: false, error: msg)}
  end

  def handle_info(
        {:map_bounds_changed,
         %{id: "earthquakes-map", center: {latitude, longitude}, zoom: zoom}},
        socket
      ) do
    patch_params(socket,
      zoom: zoom |> max(@min_zoom) |> min(@max_zoom),
      latitude: latitude |> max(@min_latitude) |> min(@max_latitude),
      longitude: normalize_longitude(longitude)
    )
  end

  def handle_event("toggle_rendering_type", %{"rendering-type" => type}, socket) do
    patch_params(socket,
      rendering_type: rendering_type_param(type, socket.assigns.rendering_type)
    )
  end

  defp patch_params(socket, overrides) do
    zoom = Keyword.get(overrides, :zoom, socket.assigns.zoom)
    latitude = Keyword.get(overrides, :latitude, socket.assigns.latitude)
    longitude = Keyword.get(overrides, :longitude, socket.assigns.longitude)
    rendering_type = Keyword.get(overrides, :rendering_type, socket.assigns.rendering_type)

    query =
      "zoom=#{zoom}" <>
        "&center=#{format_coordinate(latitude)},#{format_coordinate(longitude)}" <>
        "&rendering-type=#{rendering_type}"

    {:noreply, push_patch(socket, to: "/?#{query}", replace: true)}
  end

  defp zoom_param(nil, fallback), do: fallback

  defp zoom_param(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {zoom, ""} -> zoom |> max(@min_zoom) |> min(@max_zoom)
      _error -> fallback
    end
  end

  defp zoom_param(_value, fallback), do: fallback

  defp center_param(nil, fallback), do: fallback

  defp center_param(value, fallback) when is_binary(value) do
    with [latitude, longitude] <- String.split(value, ",", parts: 2),
         {latitude, ""} <- latitude |> String.trim() |> Float.parse(),
         {longitude, ""} <- longitude |> String.trim() |> Float.parse(),
         true <- latitude >= @min_latitude and latitude <= @max_latitude,
         true <- longitude >= @min_longitude and longitude <= @max_longitude do
      {latitude, longitude}
    else
      _error -> fallback
    end
  end

  defp center_param(_value, fallback), do: fallback

  defp rendering_type_param(value, _fallback) when value in ["vector", "raster"], do: value
  defp rendering_type_param(_value, fallback), do: fallback

  defp format_coordinate(value) when is_integer(value), do: Integer.to_string(value)

  defp format_coordinate(value) when is_float(value) do
    :erlang.float_to_binary(value, [{:decimals, 6}, :compact])
  end

  defp normalize_longitude(longitude) do
    longitude - 360.0 * :math.floor((longitude + 180.0) / 360.0)
  end

  defp notify_bounds_changed(view), do: send(self(), {:map_bounds_changed, view})

  def render(assigns) do
    ~H"""
    <div style="font-family: system-ui; max-width: 900px; margin: 0 auto; padding: 20px;">
      <div style="margin-bottom: 15px; text-align: center;">
        <h2>Global Earthquakes & Tectonic Plates 🌍</h2>
        <p style="color: #666; font-size: 14px;">
          Visualizing recent M4.5+ earthquakes (markers), plate boundaries (polylines), and tectonic plates (polygons).
          Vector mode uses LiveMap's built-in VersaTiles Colorful adaptation and zoom-aware labels.
        </p>

        <form phx-change="toggle_rendering_type" style="margin-top: 15px;">
          <label for="map-type-select" style="font-weight: bold; margin-right: 8px;">Tile Source:</label>
          <select name="rendering-type" id="map-type-select" style="padding: 6px 12px; border-radius: 6px; border: 1px solid #ccc; font-size: 14px; background-color: white; cursor: pointer;">
            <option value="vector" selected={@rendering_type == "vector"}>Vector Tiles (Shortbread/OSM)</option>
            <option value="raster" selected={@rendering_type == "raster"}>Raster Tiles (OSM Default)</option>
          </select>
        </form>
      </div>

      <div style="position: relative; height: 600px; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1); background-color: #f0fdf4;">
        <div :if={@loading?} style="position: absolute; top: 0; left: 0; right: 0; bottom: 0; display: flex; align-items: center; justify-content: center; background: rgba(255,255,255,0.7); z-index: 20;">
          <h3 style="color: #333;">Loading geological datasets...</h3>
        </div>

        <div :if={@error} style="position: absolute; top: 0; left: 0; right: 0; bottom: 0; display: flex; align-items: center; justify-content: center; background: rgba(255,255,255,0.7); z-index: 20;">
          <h3 style="color: #d9534f;">{@error}</h3>
        </div>

        <.live_component
          :if={not @loading?}
          module={LiveMap}
          id="earthquakes-map"
          center={{@latitude, @longitude}}
          zoom={@zoom}
          width={900}
          height={600}
          rendering-type={@rendering_type}
          on_bounds_changed={&notify_bounds_changed/1}
        >
          <:map_control action="pan-up">
            <span style="font-size: 16px; font-weight: 700; color: #1f2937;">↑</span>
          </:map_control>

          <:map_control action="pan-left">
            <span style="font-size: 16px; font-weight: 700; color: #1f2937;">←</span>
          </:map_control>

          <:map_control action="pan-right">
            <span style="font-size: 16px; font-weight: 700; color: #1f2937;">→</span>
          </:map_control>

          <:map_control action="pan-down">
            <span style="font-size: 16px; font-weight: 700; color: #1f2937;">↓</span>
          </:map_control>

          <:map_control action="zoom-in">
            <span style="font-size: 18px; font-weight: 700; color: #1f2937;">+</span>
          </:map_control>

          <:map_control action="zoom-out">
            <span style="font-size: 18px; font-weight: 700; color: #1f2937;">−</span>
          </:map_control>

          <:map_control action="fullscreen">
            <span style="font-size: 18px; font-weight: 700; color: #1f2937;">⛶</span>
          </:map_control>

          <:polygon
            :for={plate <- @plates}
            id={plate.id}
            points={plate.points}
            label={plate.label}
            fill="none"
            stroke="rgba(30, 144, 255, 0.4)"
            stroke-width="1"
          />

          <:polyline
            :for={boundary <- @boundaries}
            id={boundary.id}
            points={boundary.points}
            label="Plate Boundary"
            fill="none"
            stroke="rgba(255, 69, 0, 0.8)"
            stroke-width="2"
          />

          <:marker
            :for={eq <- @earthquakes}
            id={eq.id}
            position={{eq.latitude, eq.longitude}}
            title={eq.label}
          >
            <div style={"width: #{max(6, eq.mag * 2.5)}px; height: #{max(6, eq.mag * 2.5)}px; background-color: rgba(255, 0, 0, 0.6); border-radius: 50%; border: 1px solid white; box-shadow: 0 0 4px rgba(0,0,0,0.5);"}></div>
          </:marker>
        </.live_component>
      </div>
    </div>
    """
  end

  # --- Data Extraction Helpers ---

  defp extract_polygons(geojson) do
    geojson["features"]
    |> Enum.flat_map(fn feature ->
      name = (feature["properties"] || %{})["PlateName"] || "Unknown"
      geometry = feature["geometry"] || %{"type" => "Unknown"}

      case geometry["type"] do
        "Polygon" ->
          [
            %{
              id: "plate-#{name |> String.replace(" ", "-")}",
              label: name,
              points: extract_ring(hd(geometry["coordinates"]))
            }
          ]

        "MultiPolygon" ->
          geometry["coordinates"]
          |> Enum.with_index()
          |> Enum.map(fn {poly, idx} ->
            %{
              id: "plate-#{name |> String.replace(" ", "-")}-#{idx}",
              label: name,
              points: extract_ring(hd(poly))
            }
          end)

        _ ->
          []
      end
    end)
  end

  defp extract_ring(coords) do
    Enum.map(coords, fn [lon, lat | _] ->
      clamped_lat = max(-85.0511, min(85.0511, lat))
      %{latitude: clamped_lat, longitude: lon}
    end)
  end

  defp extract_polylines(geojson) do
    geojson["features"]
    |> Enum.with_index()
    |> Enum.flat_map(fn {feature, f_idx} ->
      geometry = feature["geometry"] || %{"type" => "Unknown"}

      case geometry["type"] do
        "LineString" ->
          [
            %{
              id: "boundary-#{f_idx}",
              points: extract_ring(geometry["coordinates"])
            }
          ]

        "MultiLineString" ->
          geometry["coordinates"]
          |> Enum.with_index()
          |> Enum.map(fn {line, l_idx} ->
            %{
              id: "boundary-#{f_idx}-#{l_idx}",
              points: extract_ring(line)
            }
          end)

        _ ->
          []
      end
    end)
  end

  defp extract_markers(geojson) do
    geojson["features"]
    |> Enum.flat_map(fn feature ->
      geometry = feature["geometry"] || %{"type" => "Unknown"}

      if geometry["type"] == "Point" do
        props = feature["properties"] || %{}
        [lon, lat | _] = geometry["coordinates"]
        clamped_lat = max(-85.0511, min(85.0511, lat))
        mag = props["mag"] || 4.5

        [
          %{
            id: "eq-#{feature["id"]}",
            label: props["title"] || "Earthquake",
            latitude: clamped_lat,
            longitude: lon,
            mag: mag
          }
        ]
      else
        []
      end
    end)
  end
end

PhoenixPlayground.start(live: LiveEarthquakes, open_browser: false, live_reload: false)
