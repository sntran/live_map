# LiveMap Example

The example is now a single script: `examples/live_map_demo.exs`.

Run it with:

```bash
elixir examples/live_map_demo.exs
```

Then open `http://localhost:4000`.

Useful options:

```bash
elixir examples/live_map_demo.exs --port 4010
elixir examples/live_map_demo.exs --no-start
```

The script uses `Mix.install/1` to pull Phoenix and LiveView at runtime, and loads
the local `live_map` library via a path dependency.
