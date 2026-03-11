# LiveMap Example

The example is a single script: `examples/live_maps.exs`.

Run it with:

```bash
elixir examples/live_maps.exs
```

Then open `http://localhost:4000`.

Useful options:

```bash
elixir examples/live_maps.exs --port 4010
elixir examples/live_maps.exs --no-start
```

The script uses `Mix.install/1` to pull Phoenix and LiveView at runtime, and loads
the local `live_map` library via a path dependency.
