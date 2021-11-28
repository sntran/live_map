# LiveMap

A [Phoenix LiveView](https://github.com/phoenixframework/phoenix_live_view)
Component for displaying an interactive map with dynamic data.

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
      width={800} height={600}
      latitude={10.4197639} longitude={107.1070841} zoom={11}
    >
    </.live_component>

Checkout `examples` for a Phoenix application demonstrating LiveMap usage.

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
