defmodule LiveMap.VectorTileTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias LiveMap.Tile

  setup do
    original_user_agent = Application.get_env(:live_map, :tile_user_agent)
    original_concurrency = Application.get_env(:live_map, :vector_tile_concurrency)
    original_cache_size = Application.get_env(:live_map, :vector_tile_cache_size)

    server = LiveMap.TestTileServer.start_link()
    Application.put_env(:live_map, :vector_tile_concurrency, 2)

    on_exit(fn ->
      LiveMap.TestTileServer.stop(server)

      if is_nil(original_user_agent),
        do: Application.delete_env(:live_map, :tile_user_agent),
        else: Application.put_env(:live_map, :tile_user_agent, original_user_agent)

      if is_nil(original_concurrency),
        do: Application.delete_env(:live_map, :vector_tile_concurrency),
        else: Application.put_env(:live_map, :vector_tile_concurrency, original_concurrency)

      if is_nil(original_cache_size),
        do: Application.delete_env(:live_map, :vector_tile_cache_size),
        else: Application.put_env(:live_map, :vector_tile_cache_size, original_cache_size)
    end)

    %{server: server}
  end

  test "renders inline SVG tiles for inferred MVT sources in the component", %{server: server} do
    LiveMap.TestTileServer.put_responses(server, "/0/0/0.mvt", [
      {200, [{"cache-control", "max-age=60"}], shortbread_tile()}
    ])

    rendered =
      render_component(LiveMap,
        id: "live-map",
        width: 256,
        height: 256,
        latitude: 0,
        longitude: 0,
        zoom: 0,
        sync: true,
        tile_source: %{url: server.base_url <> "/{z}/{x}/{y}.mvt"}
      )

    {:ok, document} = Floki.parse_document(rendered)

    refute Floki.find(document, "image") |> Enum.any?()
    assert [_] = Floki.find(document, "defs svg[data-live-map-source-tile='0/0/0']")
    assert [_] = Floki.find(document, "svg[data-live-map-tile-state='ready'] use")
  end

  test "renders per-tile error placeholders when vector fetches fail", %{server: server} do
    LiveMap.TestTileServer.put_responses(server, "/0/0/0.mvt", [
      {502, [{"cache-control", "max-age=0"}], "bad gateway"}
    ])

    rendered =
      render_component(LiveMap,
        id: "live-map",
        width: 256,
        height: 256,
        latitude: 0,
        longitude: 0,
        zoom: 0,
        sync: true,
        tile_source: %{url: server.base_url <> "/{z}/{x}/{y}.mvt"}
      )

    {:ok, document} = Floki.parse_document(rendered)
    [error_tile] = Floki.find(document, "svg[data-live-map-tile-state='error']")

    assert Floki.attribute(error_tile, "data-live-map-tile-error-kind") === ["fetch"]
    assert Floki.attribute(error_tile, "data-live-map-tile-error-reason") === ["http-status-502"]
  end

  test "renders decode placeholders when vector tiles are invalid", %{server: server} do
    invalid_tile =
      tile_message([layer_message("streets", [feature_message([], 4, [], 1)], [], [], 8, 2)])

    LiveMap.TestTileServer.put_responses(server, "/0/0/0.mvt", [
      {200, [{"cache-control", "max-age=60"}], invalid_tile}
    ])

    layer =
      Tile.fetch_vector_layer([%{x: 0, y: 0, z: 0}], %{url: server.base_url <> "/{z}/{x}/{y}.mvt"})

    assert [%{type: :error, error_kind: "decode", error_reason: "unsupported-geometry-type-4"}] =
             layer.tiles
  end

  test "renders transport placeholders when vector connections fail" do
    server = LiveMap.TestTileServer.start_link()
    url = server.base_url
    LiveMap.TestTileServer.stop(server)

    layer = Tile.fetch_vector_layer([%{x: 0, y: 0, z: 0}], %{url: url <> "/{z}/{x}/{y}.mvt"})

    assert [%{type: :error, error_kind: "fetch", error_reason: "econnrefused"}] = layer.tiles
  end

  test "overzoom reuses a single parent definition for sibling tiles", %{server: server} do
    LiveMap.TestTileServer.put_responses(server, "/14/0/0.mvt", [
      {200, [{"cache-control", "max-age=60"}], shortbread_tile()}
    ])

    layer =
      Tile.fetch_vector_layer(
        [
          %{x: 0, y: 0, z: 15},
          %{x: 1, y: 0, z: 15}
        ],
        %{url: server.base_url <> "/{z}/{x}/{y}.mvt"}
      )

    assert layer.source.type === :mvt
    assert layer.source.max_zoom === 14
    assert length(layer.defs) === 1
    assert length(layer.tiles) === 2

    [definition] = layer.defs
    definition_svg = definition |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    assert definition_svg =~ ~s(data-live-map-zoom="15")

    assert Enum.map(layer.tiles, fn tile -> IO.iodata_to_binary(tile.view_box) end) === [
             "0 0 0.5 0.5",
             "0.5 0 0.5 0.5"
           ]

    assert LiveMap.TestTileServer.request_count(server, "/14/0/0.mvt") === 1
  end

  test "fetches a new source tile when display coordinates collide across zooms", %{
    server: server
  } do
    LiveMap.TestTileServer.put_responses(server, "/3/2/2.mvt", [
      {200, [{"cache-control", "max-age=60"}], shortbread_tile()}
    ])

    LiveMap.TestTileServer.put_responses(server, "/2/2/2.mvt", [
      {200, [{"cache-control", "max-age=60"}], shortbread_tile()}
    ])

    source = %{url: server.base_url <> "/{z}/{x}/{y}.mvt"}
    zoom_three = Tile.fetch_vector_layer([%{x: 2, y: 2, z: 3}], source)
    zoom_two = Tile.fetch_vector_layer([%{x: 2, y: 2, z: 2}], source, "", zoom_three)

    assert [%{display_tile: "2/2/2", source_tile: "2/2/2", state: "ready"}] =
             zoom_two.tiles

    assert LiveMap.TestTileServer.request_count(server, "/3/2/2.mvt") === 1
    assert LiveMap.TestTileServer.request_count(server, "/2/2/2.mvt") === 1
  end

  test "does not fetch or decode a retained tile again after panning away", %{server: server} do
    LiveMap.TestTileServer.put_responses(server, "/1/0/0.mvt", [
      {200, [{"cache-control", "max-age=0"}], shortbread_tile()}
    ])

    LiveMap.TestTileServer.put_responses(server, "/1/1/0.mvt", [
      {200, [{"cache-control", "max-age=0"}], shortbread_tile()}
    ])

    source = %{url: server.base_url <> "/{z}/{x}/{y}.mvt"}
    first_view = Tile.fetch_vector_layer([%{x: 0, y: 0, z: 1}], source)
    panned_view = Tile.fetch_vector_layer([%{x: 1, y: 0, z: 1}], source, "", first_view)
    returned_view = Tile.fetch_vector_layer([%{x: 0, y: 0, z: 1}], source, "", panned_view)

    assert [%{display_tile: "1/0/0", state: "ready"}] = returned_view.tiles
    assert LiveMap.TestTileServer.request_count(server, "/1/0/0.mvt") === 1
    assert LiveMap.TestTileServer.request_count(server, "/1/1/0.mvt") === 1
  end

  test "reuses a decoded definition when panning across a wrapped world", %{server: server} do
    LiveMap.TestTileServer.put_responses(server, "/1/0/0.mvt", [
      {200, [{"cache-control", "max-age=0"}], shortbread_tile()}
    ])

    source = %{url: server.base_url <> "/{z}/{x}/{y}.mvt"}
    first_world = Tile.fetch_vector_layer([%{x: 0, y: 0, z: 1}], source)
    wrapped_world = Tile.fetch_vector_layer([%{x: 2, y: 0, z: 1}], source, "", first_world)

    assert [tile] = wrapped_world.tiles
    assert tile.display_tile == "1/2/0"
    assert tile.source_tile == "1/0/0"
    assert tile.state == "ready"
    assert LiveMap.TestTileServer.request_count(server, "/1/0/0.mvt") === 1
  end

  test "keeps display-zoom-specific definitions when source tiles are overzoomed", %{
    server: server
  } do
    LiveMap.TestTileServer.put_responses(server, "/14/0/0.mvt", [
      {200, [{"cache-control", "max-age=0"}], shortbread_tile()},
      {200, [{"cache-control", "max-age=0"}], shortbread_tile()}
    ])

    source = %{url: server.base_url <> "/{z}/{x}/{y}.mvt", max_zoom: 14}
    zoom_fourteen = Tile.fetch_vector_layer([%{x: 0, y: 0, z: 14}], source)
    zoom_fifteen = Tile.fetch_vector_layer([%{x: 0, y: 0, z: 15}], source, "", zoom_fourteen)

    parent_def_id = zoom_fourteen.tiles |> hd() |> Map.fetch!(:def_id)
    child_def_id = zoom_fifteen.tiles |> hd() |> Map.fetch!(:def_id)

    refute parent_def_id == child_def_id
    assert map_size(zoom_fifteen.definitions) == 2
    assert Map.has_key?(zoom_fifteen.cached_tiles, "14/0/0")
    assert Map.has_key?(zoom_fifteen.cached_tiles, "15/0/0")
    assert LiveMap.TestTileServer.request_count(server, "/14/0/0.mvt") === 2
  end

  test "evicts the least recently used offscreen tile at the configured bound", %{
    server: server
  } do
    Application.put_env(:live_map, :vector_tile_cache_size, 2)

    for x <- 0..2 do
      LiveMap.TestTileServer.put_responses(server, "/2/#{x}/0.mvt", [
        {200, [{"cache-control", "max-age=0"}], shortbread_tile()}
      ])
    end

    source = %{url: server.base_url <> "/{z}/{x}/{y}.mvt"}

    layer =
      Enum.reduce(0..2, nil, fn x, existing_layer ->
        Tile.fetch_vector_layer(
          [%{x: x, y: 0, z: 2}],
          source,
          "",
          existing_layer || %{defs: [], tiles: []}
        )
      end)

    assert map_size(layer.cached_tiles) == 2
    refute Map.has_key?(layer.cached_tiles, "2/0/0")
    assert layer.cache_order == ["2/1/0", "2/2/0"]

    returned_layer = Tile.prepare_layer([%{x: 0, y: 0, z: 2}], source, layer)
    assert [%{state: "loading", display_tile: "2/0/0"}] = returned_layer.tiles
  end

  test "streams each vector source tile as soon as it is decoded", %{server: server} do
    LiveMap.TestTileServer.put_responses(server, "/1/0/0.mvt", [
      {200, [{"cache-control", "max-age=60"}], shortbread_tile()}
    ])

    LiveMap.TestTileServer.put_responses(server, "/1/1/0.mvt", [
      {200, [{"cache-control", "max-age=60"}], shortbread_tile(), 800}
    ])

    tiles = [%{x: 0, y: 0, z: 1}, %{x: 1, y: 0, z: 1}]
    source = %{url: server.base_url <> "/{z}/{x}/{y}.mvt"}
    prepared_layer = Tile.prepare_layer(tiles, source)
    parent = self()

    Task.start(fn ->
      Tile.stream_vector_layer(tiles, source, "", prepared_layer, fn delta ->
        send(parent, {:tile_delta, delta})
      end)

      send(parent, :stream_complete)
    end)

    assert_receive {:tile_delta, %{tiles: [%{source_tile: "1/0/0", state: "ready"}]}},
                   600

    refute_received :stream_complete

    assert_receive {:tile_delta, %{tiles: [%{source_tile: "1/1/0", state: "ready"}]}},
                   1_000

    assert_receive :stream_complete
  end

  test "direct render waits for vector preparation", %{server: server} do
    LiveMap.TestTileServer.put_responses(server, "/0/0/0.mvt", [
      {200, [{"cache-control", "max-age=60"}], shortbread_tile()}
    ])

    rendered =
      %{
        id: "live-map",
        width: 256,
        height: 256,
        latitude: 0,
        longitude: 0,
        zoom: 0,
        sync: true,
        tile_source: %{url: server.base_url <> "/{z}/{x}/{y}.mvt"}
      }
      |> LiveMap.render()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert rendered =~ ~s(data-live-map-tile-state="ready")
    refute rendered =~ "<image"
  end

  test "uses the configured default user-agent for vector fetches", %{server: server} do
    Application.put_env(:live_map, :tile_user_agent, "LiveMapTest/1.0 (ops@example.com)")

    LiveMap.TestTileServer.put_responses(server, "/0/0/0.mvt", [
      {200, [{"cache-control", "max-age=60"}], shortbread_tile()}
    ])

    render_component(LiveMap,
      id: "live-map",
      width: 256,
      height: 256,
      latitude: 0,
      longitude: 0,
      zoom: 0,
      sync: true,
      tile_source: %{url: server.base_url <> "/{z}/{x}/{y}.mvt"}
    )

    [request_headers | _rest] = LiveMap.TestTileServer.request_headers(server, "/0/0/0.mvt")
    assert {"user-agent", "LiveMapTest/1.0 (ops@example.com)"} in request_headers
  end

  defp shortbread_tile do
    keys = ["kind"]
    values = [value_message(:string, "river")]

    tile_message([
      layer_message(
        "water_polygons",
        [feature_message([0, 0], 3, polygon_commands([[{0, 0}, {8, 0}, {8, 8}, {0, 8}]]), 1)],
        keys,
        values,
        8,
        2
      )
    ])
  end

  defp tile_message(layers) do
    IO.iodata_to_binary(Enum.map(layers, &field_bytes(3, &1)))
  end

  defp layer_message(name, features, keys, values, extent, version) do
    IO.iodata_to_binary([
      field_bytes(1, name),
      Enum.map(features, &field_bytes(2, &1)),
      Enum.map(keys, &field_bytes(3, &1)),
      Enum.map(values, &field_bytes(4, &1)),
      field_varint(5, extent),
      field_varint(15, version)
    ])
  end

  defp feature_message(tags, type, geometry, id) do
    IO.iodata_to_binary([
      field_varint(1, id),
      packed_field(2, tags),
      field_varint(3, type),
      packed_field(4, geometry)
    ])
  end

  defp value_message(:string, value), do: IO.iodata_to_binary(field_bytes(1, value))

  defp polygon_commands(rings) do
    {commands, _last_point} =
      Enum.reduce(rings, {[], {0, 0}}, fn [start | rest], {acc, previous_point} ->
        ring_commands = [
          command(1, 1),
          delta_pair(start, previous_point),
          command(2, length(rest)),
          encode_relative_points(rest, start),
          command(7, 1)
        ]

        {acc ++ List.flatten(ring_commands), List.last(rest, start)}
      end)

    commands
  end

  defp encode_relative_points(points, previous) do
    {encoded, _last_point} =
      Enum.map_reduce(points, previous, fn point, last_point ->
        {delta_pair(point, last_point), point}
      end)

    encoded
  end

  defp delta_pair({x, y}, {last_x, last_y}) do
    [zigzag_encode(x - last_x), zigzag_encode(y - last_y)]
  end

  defp packed_field(field_number, values) do
    packed = values |> List.flatten() |> Enum.map(&encode_varint/1)
    field_bytes(field_number, IO.iodata_to_binary(packed))
  end

  defp field_varint(field_number, value) do
    [encode_varint(command_key(field_number, 0)), encode_varint(value)]
  end

  defp field_bytes(field_number, value) do
    binary = IO.iodata_to_binary(value)
    [encode_varint(command_key(field_number, 2)), encode_varint(byte_size(binary)), binary]
  end

  defp command(id, count), do: Bitwise.bor(Bitwise.bsl(count, 3), id)

  defp command_key(field_number, wire_type),
    do: Bitwise.bor(Bitwise.bsl(field_number, 3), wire_type)

  defp zigzag_encode(value) when value >= 0, do: value * 2
  defp zigzag_encode(value), do: value * -2 - 1

  defp encode_varint(value), do: encode_varint(value, [])

  defp encode_varint(value, acc) when value < 0x80 do
    Enum.reverse([value | acc])
  end

  defp encode_varint(value, acc) do
    encode_varint(Bitwise.bsr(value, 7), [Bitwise.bor(Bitwise.band(value, 0x7F), 0x80) | acc])
  end
end
