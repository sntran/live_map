# LiveMap

A [Phoenix LiveView](https://github.com/phoenixframework/phoenix_live_view)
Component for displaying an interactive map with dynamic data.

The library is tested on Elixir 1.16+ and Phoenix LiveView 1.1.

By rendering the map on the server, it avoids the client-side map libraries
for simple mapping needs. Utilizing LiveView, we can also update map data on
the server, and let the browser do what it does best—rendering markup.

The map is rendered as an SVG, in which each tiles are rendered as `<image>`,
using tiles from OpenStreetMap's tile server by default. All the transforms
are natively handled by the browser for SVG.

Please consult and follow [usage policies](https://operations.osmfoundation.org/policies/tiles/)
of the tile servers.

## Usage

A LiveMap can be added to a LiveView by:

    <.live_component
      module={LiveMap} id="live-map"
      title="Example Live Map"
      width="800" height="600"
      latitude="10.4197639" longitude="107.1070841" zoom="11"
    >
      <%# Styles slot %>
      <:style>
        image {
          opacity: 0.75;
        }
      </:style>

      <%# Optional custom HTML zoom controls %>
      <:zoom_in>
        <span class="inline-flex h-6 w-6 items-center justify-center rounded bg-white text-slate-900">+</span>
      </:zoom_in>

      <:zoom_out>
        <span class="inline-flex h-6 w-6 items-center justify-center rounded bg-white text-slate-900">-</span>
      </:zoom_out>

      <%# A single explicit marker %>
      <:marker
        id="harbor"
        latitude={10.411379}
        longitude={107.136224}
        label="Harbor"
      />

      <%# Multiple markers via :for %>
      <:marker
        :for={marker <- @visible_markers}
        id={marker.id}
        latitude={marker.latitude}
        longitude={marker.longitude}
        label={marker.label}
      />
    </.live_component>

Run `examples/live_maps.exs` for a single-file LiveView example powered by `Mix.install/1`.

Each `:marker` slot entry must provide `latitude`, `longitude`, and `label`. The
optional `id` is used to generate a stable DOM id. LiveMap only projects and renders
the markers it receives; deciding which markers to pass remains the responsibility of
the parent LiveView. When the `:marker` slot body is omitted, LiveMap renders a
default marker dot and label. If a body is provided, it must be HTML content;
LiveMap wraps it in a `<foreignObject>` automatically. This keeps the public API
decoupled from the internal SVG rendering details while still allowing rich HTML
marker UIs. No `:let` or projected slot assigns are required. You can pass a single
marker directly, or emit multiple marker slots with `:for`.

Custom zoom controls follow the same rule: use `:zoom_in` and `:zoom_out` with
HTML content only. LiveMap wraps that content for display inside the SVG control
chrome.

HTML marker example:

    <:marker id="harbor" latitude={10.411379} longitude={107.136224} label="Harbor">
      <button class="rounded-full bg-emerald-700 px-3 py-1 text-xs font-semibold text-white">
        Harbor
      </button>
    </:marker>

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
