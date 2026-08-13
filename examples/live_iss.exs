# live_iss.exs — Live ISS Tracker demo
#
# A single-file LiveView that polls the Where the ISS at API every 3 seconds
# to track the International Space Station, rendering a live polyline trail
# over compressed, server-rendered Shortbread SVG tiles.
#
# Run:    elixir examples/live_iss.exs
# Open:   http://localhost:4000

Mix.install([
  {:phoenix_playground, "~> 0.1.8"},
  {:req, "~> 0.6"},
  {:live_map, path: Path.expand("..", __DIR__)}
])

# Vector tile fetches need an identifying User-Agent.
Application.put_env(
  :live_map,
  :tile_user_agent,
  "LiveMapISSDemo/0.1 (https://github.com/sntran/live_map)"
)

defmodule LiveISS do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(3000, self(), :tick)

    initial_pos = fetch_live_position()

    if connected?(socket) do
      :timer.send_interval(3000, self(), :tick)
      send(self(), :start_fetching_history)
    end

    {:ok,
     assign(socket,
       page_title: "Live ISS Tracker",
       current_position: initial_pos,
       historical_path: if(initial_pos, do: [initial_pos], else: []),
       live_path: if(initial_pos, do: [initial_pos], else: []),
       zoom: 3,
       selected_style: "Midnight Commander"
     )}
  end

  def handle_info(:tick, socket) do
    case fetch_live_position() do
      nil ->
        {:noreply, socket}

      new_pos ->
        new_path = Enum.take([new_pos | socket.assigns.live_path], 100)
        {:noreply, assign(socket, current_position: new_pos, live_path: new_path)}
    end
  end

  def handle_info(:start_fetching_history, socket) do
    now = System.os_time(:second)
    # Fetch 90 minutes of history at 1-minute intervals (90 points).
    # We fetch newest points first (1..90) so the tail connects immediately to the live position
    # and gracefully grows backwards as data loads.
    # The API allows max 10 timestamps per request, so we chunk them.
    chunks = Enum.map(1..90, fn i -> now - i * 60 end) |> Enum.chunk_every(10)

    if chunks != [], do: send(self(), {:fetch_chunk, chunks})
    {:noreply, socket}
  end

  def handle_info({:fetch_chunk, [chunk | rest]}, socket) do
    ts_str = Enum.join(chunk, ",")

    # Use a longer delay and retry on failure so we don't drop chunks
    case Req.get("https://api.wheretheiss.at/v1/satellites/25544/positions?timestamps=#{ts_str}",
           retry: false
         ) do
      {:ok, %{status: 200, body: positions}} ->
        # The API returns points in descending order (T-1, T-2...). 
        # We reverse them to be chronological (T-10..T-1) so they render correctly West-to-East.
        new_points =
          positions
          |> Enum.map(&%{lat: &1["latitude"], lon: &1["longitude"]})
          |> Enum.reverse()

        if rest != [] do
          Process.send_after(self(), {:fetch_chunk, rest}, 1200)
        end

        # Prepend the newly fetched older points to the front of the historical path
        updated_path = new_points ++ socket.assigns.historical_path

        {:noreply, assign(socket, historical_path: updated_path)}

      _ ->
        # If rate limited or failed, wait longer and retry the EXACT SAME chunk
        Process.send_after(self(), {:fetch_chunk, [chunk | rest]}, 2500)
        {:noreply, socket}
    end
  end

  def handle_info({:fetch_chunk, []}, socket), do: {:noreply, socket}

  def handle_event("zoom_in", _params, socket) do
    {:noreply, assign(socket, zoom: min(socket.assigns.zoom + 1, 14))}
  end

  def handle_event("zoom_out", _params, socket) do
    {:noreply, assign(socket, zoom: max(socket.assigns.zoom - 1, 0))}
  end

  def handle_event("change_style", %{"style" => style}, socket) do
    {:noreply, assign(socket, selected_style: style)}
  end

  defp fetch_live_position do
    case Req.get("https://api.wheretheiss.at/v1/satellites/25544", retry: false) do
      {:ok,
       %{
         status: 200,
         body: %{
           "latitude" => lat,
           "longitude" => lon,
           "visibility" => vis,
           "solar_lat" => slat,
           "solar_lon" => slon
         }
       }} ->
        %{lat: lat, lon: lon, visibility: vis, solar_lat: slat, solar_lon: slon}

      _ ->
        nil
    end
  end

  defp terminator_polygon(solar_lat, solar_lon) do
    epsilon = 0.0001
    slat_rad = solar_lat * :math.pi() / 180.0
    slon_rad = solar_lon * :math.pi() / 180.0

    slat_rad =
      if abs(slat_rad) < epsilon do
        if slat_rad < 0, do: -epsilon, else: epsilon
      else
        slat_rad
      end

    curve =
      Enum.map(-1080..1080//2, fn lon ->
        lon_rad = lon * :math.pi() / 180.0
        tan_lat = -:math.cos(lon_rad - slon_rad) / :math.tan(slat_rad)
        lat = :math.atan(tan_lat) * 180.0 / :math.pi()
        %{latitude: lat, longitude: lon}
      end)

    # Cap the poles at the Web Mercator limit (±85.0511 degrees)
    night_pole = if solar_lat > 0, do: -85.0511, else: 85.0511

    bottom_edge =
      Enum.map(1080..-1080//-2, fn lon ->
        %{latitude: night_pole, longitude: lon}
      end)

    curve ++ bottom_edge
  end

  def map_style(name) do
    filename =
      name
      |> String.downcase()
      |> String.replace(" ", "-")
      |> Kernel.<>(".json")

    path = Path.join([__DIR__, "styles", filename])

    case File.read(path) do
      {:ok, content} -> Phoenix.json_library().decode!(content)
      {:error, _} -> []
    end
  end

  defp vector_tile_source(style) do
    slug =
      style
      |> String.downcase()
      |> String.replace(" ", "-")

    %{url: "/vector/#{slug}/{zoom}/{x}/{y}.svg"}
  end

  def render(assigns) do
    ~H"""
    <div style="font-family: system-ui; max-width: 800px; margin: 0 auto; padding: 20px;">
      <div style="margin-bottom: 15px; text-align: center;">
        <h2>Live ISS Tracker 🛰️</h2>
        <p :if={@current_position} style="color: #666; font-weight: bold; font-variant-numeric: tabular-nums;">
          Lat: {@current_position.lat} | Lon: {@current_position.lon} | {@current_position.visibility |> to_string() |> String.capitalize()}
        </p>
        <p :if={is_nil(@current_position)} style="color: #666; font-weight: bold;">
          Locating station...
        </p>
        
        <form phx-change="change_style" style="margin-top: 15px;">
          <label for="style-select" style="font-weight: bold; margin-right: 8px;">Map Style:</label>
          <select name="style" id="style-select" style="padding: 6px 12px; border-radius: 6px; border: 1px solid #ccc; font-size: 14px; background-color: white; cursor: pointer;">
            <option value="Midnight Commander" selected={@selected_style == "Midnight Commander"}>Midnight Commander</option>
            <option value="Blue Water" selected={@selected_style == "Blue Water"}>Blue Water</option>
            <option value="Pale Dawn" selected={@selected_style == "Pale Dawn"}>Pale Dawn</option>
          </select>
        </form>
      </div>

      <div style="position: relative; height: 600px; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1); background-color: #f0fdf4;">
        <div style="position: absolute; bottom: 20px; right: 20px; z-index: 10; display: flex; flex-direction: column; gap: 8px;">
          <button phx-click="zoom_in" style="width: 36px; height: 36px; border-radius: 8px; border: 1px solid #ccc; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.2); font-size: 20px; font-weight: bold; cursor: pointer; display: flex; align-items: center; justify-content: center; padding-bottom: 2px;">+</button>
          <button phx-click="zoom_out" style="width: 36px; height: 36px; border-radius: 8px; border: 1px solid #ccc; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.2); font-size: 20px; font-weight: bold; cursor: pointer; display: flex; align-items: center; justify-content: center; padding-bottom: 2px;">-</button>
        </div>

        <.live_component
          :if={@current_position}
          module={LiveMap}
          id="iss-tracker-map"
          center={{@current_position.lat, @current_position.lon}}
          zoom={@zoom}
          width={800}
          height={600}
          tile_source={vector_tile_source(@selected_style)}
          styles={map_style(@selected_style)}
        >
          <:style>{"
            /* Night Terminator layer */
            [data-live-map-shape-id='night-terminator'] {
              fill: #1e293b;
              fill-opacity: 0.85;
              stroke: none;
              pointer-events: none;
            }

            /* Make the polyline trail pop */
            .live-map-polyline {
              stroke: #fde047 !important;
              stroke-width: 2 !important;
              stroke-linejoin: round !important;
              stroke-linecap: round !important;
            }
          "}</:style>

          <:polygon
            id="night-terminator"
            points={terminator_polygon(@current_position.solar_lat, @current_position.solar_lon)}
            fill="rgba(2, 6, 23, 0.65)"
            stroke="none"
            style="pointer-events: none;"
          />

          <:polyline
            id="historical-orbit"
            points={Enum.map(@historical_path, & %{latitude: &1.lat, longitude: &1.lon})}
            label="Past 90 Minutes"
          />

          <:polyline
            id="iss-live-path"
            points={Enum.map(@live_path, & %{latitude: &1.lat, longitude: &1.lon})}
            label="Live Track"
          />

          <:marker id="iss" position={{@current_position.lat, @current_position.lon}} title="ISS">
            <div style="font-size: 32px; filter: drop-shadow(0px 0px 8px rgba(56, 189, 248, 0.8));">🛰️</div>
          </:marker>

        </.live_component>
      </div>
    </div>
    """
  end
end

defmodule LiveISSRouter do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:put_root_layout, html: {PhoenixPlayground.Layout, :root})
    plug(:put_secure_browser_headers)
  end

  scope "/" do
    pipe_through(:browser)

    live("/", LiveISS)
  end

  forward("/vector/midnight-commander", LiveMap.VectorTile.Plug,
    source: LiveMap.Tile.default_vector_source(),
    base_style: "colorful",
    styles: LiveISS.map_style("Midnight Commander"),
    max_display_zoom: 22,
    max_age: 86_400,
    compress: true
  )

  forward("/vector/blue-water", LiveMap.VectorTile.Plug,
    source: LiveMap.Tile.default_vector_source(),
    base_style: "colorful",
    styles: LiveISS.map_style("Blue Water"),
    max_display_zoom: 22,
    max_age: 86_400,
    compress: true
  )

  forward("/vector/pale-dawn", LiveMap.VectorTile.Plug,
    source: LiveMap.Tile.default_vector_source(),
    base_style: "colorful",
    styles: LiveISS.map_style("Pale Dawn"),
    max_display_zoom: 22,
    max_age: 86_400,
    compress: true
  )
end

PhoenixPlayground.start(plug: LiveISSRouter, open_browser: false, live_reload: false)
