# LiveMap

A [Phoenix LiveView](https://github.com/phoenixframework/phoenix_live_view)
Component for displaying an interactive map with dynamic data.

The library is tested on Elixir 1.16+ and Phoenix LiveView 1.1.

By rendering the map on the server, it avoids the client-side map libraries
for simple mapping needs. Utilizing LiveView, we can also update map data on
the server, and let the browser do what it does best—rendering markup.

The map is rendered as an SVG. Raster sources are emitted as `<image>` tiles by
default, while Shortbread-compatible vector sources are fetched and decoded on
the server into nested SVG tiles. All the transforms are natively handled by
the browser for SVG.

Please consult and follow [usage policies](https://operations.osmfoundation.org/policies/tiles/)
of the tile servers.

## Usage

A LiveMap can be added to a LiveView by:

    <.live_component
      module={LiveMap} id="live-map"
      title="Example Live Map"
      width="800" height="600"
      center="10.4197639,107.1070841" zoom="11"
      rendering-type="vector"
    >
      <%# Styles slot %>
      <:style>
        /* CSS custom variables or class selectors to customize map colors */
        :root {
          --live-map-water-fill: #38bdf8;
          --live-map-land-fill: #fef08a;
        }
        .live-map-shortbread-role-building {
          fill: #cbd5e1;
        }
      </:style>

      <%# Optional custom HTML zoom controls %>
      <:zoom_in>
        <span class="inline-flex h-6 w-6 items-center justify-center rounded bg-white text-slate-900">+</span>
      </:zoom_in>

      <:zoom_out>
        <span class="inline-flex h-6 w-6 items-center justify-center rounded bg-white text-slate-900">-</span>
      </:zoom_out>

      <%# Optional SVG overlays projected from map coordinates %>
      <:polygon
        id="district"
        label="Sample district"
        points={[
          %{latitude: 10.34, longitude: 107.07},
          %{latitude: 10.35, longitude: 107.09},
          %{latitude: 10.33, longitude: 107.11}
        ]}
      />

      <:polyline
        id="route"
        label="Sample route"
        points={[
          %{latitude: 10.34, longitude: 107.07},
          %{latitude: 10.36, longitude: 107.10},
          %{latitude: 10.38, longitude: 107.13}
        ]}
      />

      <%# A single explicit marker %>
      <:marker
        id="harbor"
        position="10.411379,107.136224"
        title="Harbor"
      />

      <%# Add a slot body to <:marker> when you want custom HTML marker UI. %>

      <%# Multiple markers via :for %>
      <:marker
        :for={marker <- @visible_markers}
        id={marker.id}
        position={{marker.latitude, marker.longitude}}
        title={marker.label}
      />
    </.live_component>

Run `examples/live_maps.exs` for a single-file LiveView example powered by `Mix.install/1`.

Zoom controls are opt-in: LiveMap renders no zoom buttons by default. Add the
`:zoom_in` and/or `:zoom_out` slots with HTML content to enable them, such as
for interactive LiveView output.

Each `:marker` slot entry must provide `position` and `title`. The
optional `id` is used to generate a stable DOM id. LiveMap only projects and renders
the markers it receives; deciding which markers to pass remains the responsibility of
the parent LiveView. When the `:marker` slot body is omitted, LiveMap renders a
default SVG marker pin with the marker title exposed through the SVG title. If a body is provided, it must be HTML content;
LiveMap wraps it in a `<foreignObject>` automatically. This keeps the public API
decoupled from the internal SVG rendering details while still allowing rich HTML
marker UIs. No `:let` or projected slot assigns are required. You can pass a single
marker directly, or emit multiple marker slots with `:for`.

Like Google's [`<gmp-map>`](https://developers.google.com/maps/documentation/javascript/reference/map)
and [`<gmp-advanced-marker>`](https://developers.google.com/maps/documentation/javascript/reference/advanced-markers)
elements, `center` and `position` accept a `"latitude,longitude"` string.
Elixir callers may also pass a
`{latitude, longitude}` tuple or `%{lat: latitude, lng: longitude}` map.
The map-level `latitude` and `longitude` attributes and the marker-level
`latitude`, `longitude`, and `label` attributes are deprecated compatibility
fallbacks. When both forms are supplied, `center`, `position`, and `title` win.

Custom zoom controls follow the same rule: use `:zoom_in` and `:zoom_out` with
HTML content only. LiveMap wraps that content for display inside the SVG control
chrome.

Polygon and polyline overlays are projected in map coordinates and rendered as
SVG shapes on their own layer. Each `:polygon` or `:polyline` slot accepts a
`points` list of `%{latitude: ..., longitude: ...}` maps, with optional `id`
and `label` attributes. LiveMap renders default SVG `<polygon>` and `<polyline>`
elements for these overlays.

HTML marker example:

    <:marker id="harbor" position="10.411379,107.136224" title="Harbor">
      <button class="rounded-full bg-emerald-700 px-3 py-1 text-xs font-semibold text-white">
        Harbor
      </button>
    </:marker>

## Rendering Type and Tile Sources

Set `rendering-type` to the `raster|vector` enum to select LiveMap's built-in
OpenStreetMap raster or Shortbread vector source. LiveMap keeps raster as the
default for backward compatibility:

```elixir
<.live_component
  module={LiveMap}
  id="live-map"
  center="10.4197639,107.1070841"
  zoom={11}
  rendering-type="raster"
/>
```

Use `rendering-type="vector"` to switch to the built-in OSM vector source
without configuring `tile_source`. The optional Req dependency is required for
vector rendering.

`tile_source` remains supported for backward compatibility and custom tile
servers. If both attributes are supplied, `rendering-type` selects the built-in
source.

Tile source type is inferred from the URL by default: `.mvt` and `.pbf` URLs are
treated as vector sources, everything else is treated as raster.

Shortbread MVT sources are server-rendered and support overzoom above level 14:

```elixir
<.live_component
  module={LiveMap}
  id="live-map"
  center="10.4197639,107.1070841"
  zoom={15}
  tile_source={%{
    url: "https://vector.openstreetmap.org/$VERSION/{zoom}/{x}/{y}.mvt",
    version: "shortbread_v1",
    max_zoom: 14,
    headers: [{"x-example-header", "demo"}]
  }}
/>
```

### Built-in vector style

Vector maps use an SVG adaptation of the open source
[VersaTiles Colorful](https://github.com/versatiles-org/versatiles-style) style
for Shortbread tiles out of the box. The defaults include its land, water,
road, building, boundary, and label palette plus a conservative label policy:
country labels appear first, followed by capitals, cities, towns, and smaller
places as the map zooms in. State/region labels are held back until zoom 7,
and dense address and point-of-interest layers are hidden. Shortbread's English
name is preferred when one is available.

The built-in rules are applied before `styles`, so a Google Maps style JSON
from a service such as Snazzy Maps can recolor the map or explicitly show and
hide features:

```elixir
styles = "priv/map_style.json" |> File.read!() |> Jason.decode!()

<.live_component
  module={LiveMap}
  id="styled-map"
  center="10.4197639,107.1070841"
  zoom={11}
  rendering-type="vector"
  styles={styles}
/>
```

LiveMap supports the common Google style fields used for feature visibility,
color, and stroke weight. The CSS custom properties shown in the main usage
example remain available for smaller overrides without a style JSON.

The tile source URL may use `{zoom}` or `{z}`, plus `{x}`, `{y}`, `{version}`,
and `$VERSION` placeholders. `version` is only required when the URL contains a
version placeholder. Only absolute `http` and `https` URLs are accepted.

If you use vector sources from another application, include the optional Req
dependency there as well:

```elixir
def deps do
  [
    {:live_map, "~> 0.0.1"},
    {:req, "~> 0.6.2"}
  ]
end
```

For server-side tile fetches, configure an identifying default User-Agent:

```elixir
config :live_map, :tile_user_agent,
  "MyApp/1.0 (contact@example.com)"
```

Per-source headers are optional and are merged with that default.

Live components publish each decoded vector source tile as soon as it is ready.
Concurrent fetch/decode work defaults to the smaller of eight tasks or the
number of online schedulers, and can be tuned for the tile service and host:

```elixir
config :live_map, :vector_tile_concurrency, 4
```

Decoded vector tiles are retained in a per-map LRU cache, so panning back to a
recent area does not fetch or decode those tiles again. While zooming in, the
nearest cached parent tile is cropped and scaled as a placeholder until the
requested child tile finishes loading. The cache defaults to 64 display tiles;
set it to `0` to disable retention or tune it for the memory available to each
LiveView process:

```elixir
config :live_map, :vector_tile_cache_size, 96
```

## CLI

The escript still renders raster output by default:

```bash
./live_map --latitude 10.4197639 --longitude 107.1070841 --zoom 11 --width 640 --height 360 > map.svg
```

To emit self-contained vector SVG, point the CLI at an MVT source:

```bash
./live_map \
  --latitude 10.4197639 \
  --longitude 107.1070841 \
  --zoom 15 \
  --width 640 \
  --height 360 \
  --tile-url 'https://vector.openstreetmap.org/$VERSION/{zoom}/{x}/{y}.mvt' \
  --tile-version shortbread_v1 \
  --tile-user-agent 'MyApp/1.0 (contact@example.com)' \
  > map.svg
```

## Operational Notes

- Vector tile rendering moves tile fetching and decoding onto your server. Treat `tile_source` as trusted application configuration, not as untrusted request input.
- LiveMap fetches vector tiles through Req and enables Req's HTTP cache for repeated requests.
- Remote tile sources can increase server load and can expose SSRF risks if you allow untrusted users to control URLs or headers.
- Continue to display proper OpenStreetMap attribution and follow the upstream tile usage policies for whatever raster or vector service you configure.
- The OpenStreetMap vector service at `vector.openstreetmap.org` requires a valid identifying User-Agent, local caching, and no `no-cache` request headers. Review the current policy before shipping against it.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `live_map` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:live_map, "~> 0.0.1"}
  ]
end
```

Documentation is generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/live_map](https://hexdocs.pm/live_map).
