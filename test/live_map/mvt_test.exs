defmodule LiveMap.MVTTest do
  use ExUnit.Case, async: true

  alias LiveMap.MVT

  test "decodes a handcrafted shortbread-style tile into aggregated SVG paths" do
    tile = shortbread_fixture_tile()

    assert {:ok, svg} = MVT.decode(tile)

    rendered = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

    assert rendered =~ ~s(data-live-map-tile-format="mvt")
    assert rendered =~ ~s(class="live-map-shortbread-feature live-map-shortbread-role-water)
    assert rendered =~ ~s(class="live-map-shortbread-feature live-map-shortbread-role-street)
    assert rendered =~ ~s(class="live-map-shortbread-feature live-map-shortbread-role-site)
    assert rendered =~ ~s(fill-rule="evenodd")
    assert rendered =~ ~s(d="M0 0L1 0L1 1L0 1ZM0.25 0.25L0.75 0.25L0.75 0.75L0.25 0.75Z")
    assert rendered =~ ~s(d="M0 0.5L1 0.5")
    assert rendered =~ ~s(A0.01 0.01 0 1 0)
    refute rendered =~ "<script>"
  end

  test "decodes gzip-compressed MVT input" do
    tile = shortbread_fixture_tile()

    assert {:ok, svg} = tile |> :zlib.gzip() |> MVT.decode()

    rendered = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    assert rendered =~ ~s(data-live-map-tile-format="mvt")
  end

  test "decodes the checked-in fixture file" do
    tile =
      "/home/esente/Projects/sntran/live_map/test/fixtures/shortbread_fixture.mvt.base64"
      |> File.read!()
      |> String.trim()
      |> Base.decode64!()

    assert {:ok, svg} = MVT.decode(tile)

    rendered = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    assert rendered =~ ~s(data-live-map-tile-format="mvt")
    assert rendered =~ ~s(live-map-shortbread-role-water)
  end

  test "rejects unsupported layer versions" do
    tile =
      tile_message([
        layer_message("water_polygons", [], [], [], 8, 1)
      ])

    assert {:error, {:unsupported_layer_version, 1}} = MVT.decode(tile)
  end

  test "rejects truncated geometry data" do
    feature =
      feature_message(
        [0, 0],
        3,
        [command(1, 1), zigzag_encode(0)],
        1
      )

    tile =
      tile_message([
        layer_message(
          "water_polygons",
          [feature],
          ["kind"],
          [value_message(:string, "river")],
          8,
          2
        )
      ])

    assert {:error, :truncated_geometry} = MVT.decode(tile)
  end

  test "renders supported style variants across roles and kinds" do
    assert {:ok, svg} = MVT.decode(style_matrix_tile())

    rendered = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

    assert rendered =~ ~s(live-map-shortbread-role-land)
    assert rendered =~ ~s(live-map-shortbread-role-building)
    assert rendered =~ ~s(live-map-shortbread-role-bridge)
    assert rendered =~ ~s(live-map-shortbread-role-boundary)
    assert rendered =~ ~s(live-map-shortbread-role-pier)
    assert rendered =~ ~s(live-map-shortbread-role-ferry)
    assert rendered =~ ~s(live-map-shortbread-role-aerialway)
    assert rendered =~ ~s(live-map-shortbread-role-other)
    assert rendered =~ ~s(live-map-shortbread-bridge)
    assert rendered =~ ~s(live-map-shortbread-tunnel)

    # Styles are embedded in each tile SVG's own <style> block, not as path presentation attributes
    refute rendered =~ ~s(fill="#)
    refute rendered =~ ~s(stroke="#)
    assert rendered =~ "<style>"
    assert rendered =~ "#bfd7b5"
    assert rendered =~ "#cbe3bc"
    assert rendered =~ "#d8ccbe"
    assert rendered =~ "#5aa7da"
  end

  test "defaults missing layer extents to 4096" do
    tile =
      tile_message([
        layer_message_without_extent(
          "streets",
          [feature_message([0, 0], 2, line_commands([line_segment(0, 0, 4096, 4096)]), 1)],
          ["kind"],
          [value_message(:string, "service")],
          2
        )
      ])

    assert {:ok, svg} = MVT.decode(tile)

    rendered = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    assert rendered =~ ~s(d="M0 0L1 1")
  end

  test "renders merged river lines, site polygons, and default layer tokens" do
    tile =
      tile_message([
        layer_message(
          "water_lines",
          [
            feature_message(
              [0, 0],
              2,
              line_commands([line_segment(0, 0, 4, 0), line_segment(0, 1, 4, 1)]),
              1
            ),
            feature_message([0, 0], 2, line_commands([line_segment(0, 2, 4, 2)]), 2)
          ],
          ["kind"],
          [value_message(:string, "river")],
          8,
          2
        ),
        layer_message(
          "sites",
          [feature_message([], 3, polygon_commands([square(0, 4, 2)]), 3)],
          ["kind"],
          [value_message(:string, "river")],
          8,
          2
        ),
        layer_message(
          "!!!",
          [feature_message([], 1, point_commands([{4, 4}]), 4)],
          ["kind"],
          [value_message(:string, "river")],
          8,
          2
        )
      ])

    assert {:ok, svg} = MVT.decode(tile)

    rendered = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    assert rendered =~ ~s(live-map-shortbread-role-water)
    assert rendered =~ ~s(live-map-shortbread-kind-river)
    assert rendered =~ ~s(live-map-shortbread-role-site)
    assert rendered =~ ~s(live-map-shortbread-layer-default)
  end

  test "rejects malformed tags, geometry commands, and missing geometry types" do
    polygon = polygon_commands([square(0, 0, 4)])

    cases = [
      {:odd_number_of_tags,
       single_feature_tile(
         "water_polygons",
         ["kind"],
         [value_message(:string, "river")],
         [0],
         3,
         polygon
       )},
      {:invalid_key_index,
       single_feature_tile(
         "water_polygons",
         ["kind"],
         [value_message(:string, "river")],
         [1, 0],
         3,
         polygon
       )},
      {:invalid_value_index,
       single_feature_tile(
         "water_polygons",
         ["kind"],
         [value_message(:string, "river")],
         [0, 1],
         3,
         polygon
       )},
      {:missing_geometry_type,
       tile_message([
         layer_message(
           "water_polygons",
           [feature_message_without_type([0, 0], polygon, 1)],
           ["kind"],
           [value_message(:string, "river")],
           8,
           2
         )
       ])},
      {{:unsupported_geometry_type, 4},
       single_feature_tile(
         "water_polygons",
         ["kind"],
         [value_message(:string, "river")],
         [0, 0],
         4,
         []
       )},
      {:invalid_command_count,
       single_feature_tile("place_labels", [], [], [], 1, [command(1, 0)])},
      {:lineto_without_moveto,
       single_feature_tile("streets", [], [], [], 2, [
         command(2, 1),
         zigzag_encode(1),
         zigzag_encode(0)
       ])},
      {:invalid_linestring_moveto_count,
       single_feature_tile("streets", [], [], [], 2, [command(1, 2), 0, 0, 2, 2])},
      {:linestring_too_short,
       single_feature_tile("streets", [], [], [], 2, [command(1, 1), 0, 0])},
      {{:illegal_command, 7, :line},
       single_feature_tile("streets", [], [], [], 2, [command(7, 1)])},
      {:unterminated_polygon_ring,
       single_feature_tile("water_polygons", [], [], [], 3, [
         command(1, 1),
         0,
         0,
         command(2, 2),
         2,
         0,
         0,
         2
       ])},
      {:moveto_before_closepath,
       single_feature_tile("water_polygons", [], [], [], 3, [
         command(1, 1),
         0,
         0,
         command(1, 1),
         2,
         2
       ])},
      {:invalid_polygon_moveto_count,
       single_feature_tile("water_polygons", [], [], [], 3, [command(1, 2), 0, 0, 2, 0])},
      {:invalid_closepath_count,
       single_feature_tile("water_polygons", [], [], [], 3, [
         command(1, 1),
         0,
         0,
         command(2, 2),
         2,
         0,
         0,
         2,
         command(7, 2)
       ])},
      {:polygon_ring_too_short,
       single_feature_tile("water_polygons", [], [], [], 3, [
         command(1, 1),
         0,
         0,
         command(2, 1),
         2,
         0,
         command(7, 1)
       ])},
      {:degenerate_polygon_ring,
       single_feature_tile("water_polygons", [], [], [], 3, [
         command(1, 1),
         0,
         0,
         command(2, 2),
         2,
         0,
         2,
         0,
         command(7, 1)
       ])},
      {{:illegal_command, 3, :polygon},
       single_feature_tile("water_polygons", [], [], [], 3, [command(3, 1)])}
    ]

    Enum.each(cases, fn {expected, tile} ->
      assert {:error, ^expected} = MVT.decode(tile)
    end)
  end

  test "rejects malformed values and protobuf payloads" do
    keys = ["kind"]
    point = point_commands([{0, 0}])

    unsupported_packed_feature =
      raw_feature([
        field_varint(1, 1),
        field_fixed32(2, 1.25),
        field_varint(3, 1),
        packed_field(4, point)
      ])

    value_cases = [
      {:empty_value_message, single_feature_tile("water_polygons", keys, [""], [0, 0], 1, point)},
      {:unsupported_value_encoding,
       single_feature_tile(
         "water_polygons",
         keys,
         [IO.iodata_to_binary(field_varint(7, 2))],
         [0, 0],
         1,
         point
       )},
      {:truncated_fixed32,
       single_feature_tile(
         "water_polygons",
         keys,
         [IO.iodata_to_binary([encode_varint(command_key(2, 5)), <<1, 2, 3>>])],
         [0, 0],
         1,
         point
       )},
      {:truncated_fixed64,
       single_feature_tile(
         "water_polygons",
         keys,
         [IO.iodata_to_binary([encode_varint(command_key(3, 1)), <<1, 2, 3, 4, 5, 6, 7>>])],
         [0, 0],
         1,
         point
       )},
      {{:unsupported_packed_field, 2},
       tile_message([
         layer_message(
           "water_polygons",
           [unsupported_packed_feature],
           keys,
           [value_message(:string, "river")],
           8,
           2
         )
       ])}
    ]

    protobuf_cases = [
      {:invalid_gzip, <<0x1F, 0x8B, 0x08, 0x00>>},
      {:invalid_field_number, <<0>>},
      {:truncated_length_delimited, <<0x1A, 0x02, 0x01>>},
      {:truncated_varint, <<0x80>>},
      {:varint_overflow, :binary.copy(<<0x80>>, 11)},
      {{:unsupported_wire_type, 3}, <<0x1B>>}
    ]

    Enum.each(value_cases ++ protobuf_cases, fn {expected, tile} ->
      assert {:error, ^expected} = MVT.decode(tile)
    end)
  end

  test "accepts unpacked varints and rejects missing layer metadata" do
    unpacked_feature =
      raw_feature([
        field_varint(1, 1),
        field_varint(2, 0),
        field_varint(2, 0),
        field_varint(3, 1),
        field_varint(4, command(1, 1)),
        field_varint(4, 0),
        field_varint(4, 0)
      ])

    success_tile =
      tile_message([
        layer_message(
          "place_labels",
          [unpacked_feature],
          ["kind"],
          [value_message(:string, "school")],
          8,
          2
        )
      ])

    assert {:ok, svg} = MVT.decode(success_tile)

    assert svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary() =~
             ~s(live-map-shortbread-role-site)

    missing_cases = [
      {:missing_layer_name, tile_message([raw_layer([field_varint(5, 8), field_varint(15, 2)])])},
      {:missing_layer_version,
       tile_message([raw_layer([field_bytes(1, "water_polygons"), field_varint(5, 8)])])},
      {:truncated_varint,
       tile_message([
         layer_message(
           "place_labels",
           [
             raw_feature([
               field_varint(1, 1),
               packed_field(2, []),
               field_varint(3, 1),
               field_bytes(4, <<0x80>>)
             ])
           ],
           [],
           [],
           8,
           2
         )
       ])}
    ]

    Enum.each(missing_cases, fn {expected, tile} ->
      assert {:error, ^expected} = MVT.decode(tile)
    end)
  end

  defp shortbread_fixture_tile do
    keys = [
      "kind",
      "bridge",
      "name",
      "amenity",
      "dummy_float",
      "dummy_uint",
      "dummy_sint",
      "dummy_bool",
      "dummy_double",
      "dummy_int"
    ]

    values = [
      value_message(:string, "river"),
      value_message(:bool, true),
      value_message(:string, "<script>alert(1)</script>"),
      value_message(:string, "motorway"),
      value_message(:string, "school"),
      value_message(:float, 1.25),
      value_message(:uint, 42),
      value_message(:sint, -3),
      value_message(:bool, false),
      value_message(:double, 2.5),
      value_message(:int, 7)
    ]

    water_feature =
      feature_message(
        [
          0,
          0,
          2,
          2,
          4,
          5,
          7,
          6
        ],
        3,
        polygon_commands([
          [{0, 0}, {8, 0}, {8, 8}, {0, 8}],
          [{2, 2}, {6, 2}, {6, 6}, {2, 6}]
        ]),
        11
      )

    street_feature =
      feature_message(
        [0, 3, 1, 1],
        2,
        line_commands([
          [{0, 4}, {8, 4}]
        ]),
        12
      )

    point_feature =
      feature_message(
        [3, 4, 2, 2],
        1,
        point_commands([{4, 4}]),
        13
      )

    tile_message([
      layer_message("water_polygons", [water_feature], keys, values, 8, 2, unknown_field()),
      layer_message("streets", [street_feature], keys, values, 8, 2),
      layer_message("place_labels", [point_feature], keys, values, 8, 2)
    ])
  end

  defp unknown_field do
    field_bytes(9, "ignored")
  end

  defp tile_message(layers) do
    IO.iodata_to_binary(Enum.map(layers, &field_bytes(3, &1)))
  end

  defp single_feature_tile(layer_name, keys, values, tags, type, geometry) do
    tile_message([
      layer_message(
        layer_name,
        [feature_message(tags, type, geometry, 1)],
        keys,
        values,
        8,
        2
      )
    ])
  end

  defp layer_message(name, features, keys, values, extent, version, extra \\ []) do
    IO.iodata_to_binary([
      field_bytes(1, name),
      Enum.map(features, &field_bytes(2, &1)),
      Enum.map(keys, &field_bytes(3, &1)),
      Enum.map(values, &field_bytes(4, &1)),
      field_varint(5, extent),
      field_varint(15, version),
      extra
    ])
  end

  defp layer_message_without_extent(name, features, keys, values, version, extra \\ []) do
    IO.iodata_to_binary([
      field_bytes(1, name),
      Enum.map(features, &field_bytes(2, &1)),
      Enum.map(keys, &field_bytes(3, &1)),
      Enum.map(values, &field_bytes(4, &1)),
      field_varint(15, version),
      extra
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

  defp feature_message_without_type(tags, geometry, id) do
    IO.iodata_to_binary([
      field_varint(1, id),
      packed_field(2, tags),
      packed_field(4, geometry)
    ])
  end

  defp raw_feature(fields), do: IO.iodata_to_binary(fields)
  defp raw_layer(fields), do: IO.iodata_to_binary(fields)

  defp value_message(:string, value), do: IO.iodata_to_binary(field_bytes(1, value))
  defp value_message(:float, value), do: IO.iodata_to_binary(field_fixed32(2, value))
  defp value_message(:double, value), do: IO.iodata_to_binary(field_fixed64(3, value))
  defp value_message(:int, value), do: IO.iodata_to_binary(field_varint(4, value))
  defp value_message(:uint, value), do: IO.iodata_to_binary(field_varint(5, value))
  defp value_message(:sint, value), do: IO.iodata_to_binary(field_varint(6, zigzag_encode(value)))
  defp value_message(:bool, true), do: IO.iodata_to_binary(field_varint(7, 1))
  defp value_message(:bool, false), do: IO.iodata_to_binary(field_varint(7, 0))

  defp point_commands(points) do
    [command(1, length(points)) | encode_point_deltas(points, {0, 0})]
  end

  defp line_commands(parts) do
    {commands, _last_point} =
      Enum.reduce(parts, {[], {0, 0}}, fn [start | rest], {acc, previous_point} ->
        part_commands = [
          command(1, 1),
          delta_pair(start, previous_point),
          command(2, length(rest)),
          encode_relative_points(rest, start)
        ]

        {acc ++ List.flatten(part_commands), List.last(rest, start)}
      end)

    commands
  end

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

  defp encode_point_deltas([], _previous), do: []

  defp encode_point_deltas([point | rest], previous) do
    [delta_pair(point, previous) | encode_point_deltas(rest, point)]
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

  defp field_fixed32(field_number, value) do
    [encode_varint(command_key(field_number, 5)), <<value::little-float-size(32)>>]
  end

  defp field_fixed64(field_number, value) do
    [encode_varint(command_key(field_number, 1)), <<value::little-float-size(64)>>]
  end

  defp style_matrix_tile do
    keys = ["kind", "bridge", "tunnel"]

    values = [
      value_message(:string, "canal"),
      value_message(:string, "stream"),
      value_message(:string, "ditch"),
      value_message(:string, "forest"),
      value_message(:string, "park"),
      value_message(:string, "grass"),
      value_message(:string, "farmland"),
      value_message(:string, "sand"),
      value_message(:string, "beach"),
      value_message(:string, "scrub"),
      value_message(:string, "runway"),
      value_message(:string, "taxiway"),
      value_message(:string, "trunk"),
      value_message(:string, "primary"),
      value_message(:string, "secondary"),
      value_message(:string, "tertiary"),
      value_message(:string, "rail"),
      value_message(:string, "tram"),
      value_message(:string, "subway"),
      value_message(:string, "service"),
      value_message(:int, 1),
      value_message(:string, "true")
    ]

    tile_message([
      layer_message(
        "water_lines",
        [
          feature_message([0, 0], 2, line_commands([line_segment(0, 0, 4, 0)]), 1),
          feature_message([0, 1], 2, line_commands([line_segment(0, 1, 4, 1)]), 2),
          feature_message([0, 2], 2, line_commands([line_segment(0, 2, 4, 2)]), 3)
        ],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "land",
        [
          feature_message([0, 3], 3, polygon_commands([square(0, 4, 2)]), 4),
          feature_message([0, 4], 3, polygon_commands([square(3, 4, 2)]), 5),
          feature_message([0, 5], 3, polygon_commands([square(6, 4, 2)]), 6),
          feature_message([0, 6], 3, polygon_commands([square(9, 4, 2)]), 7),
          feature_message([0, 7], 3, polygon_commands([square(12, 4, 2)]), 8),
          feature_message([0, 8], 3, polygon_commands([square(15, 4, 2)]), 9),
          feature_message([0, 9], 3, polygon_commands([square(18, 4, 2)]), 10)
        ],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "street_polygons",
        [
          feature_message([0, 10], 3, polygon_commands([square(0, 8, 2)]), 11),
          feature_message([0, 11], 3, polygon_commands([square(3, 8, 2)]), 12),
          feature_message([0, 19], 3, polygon_commands([square(6, 8, 2)]), 13)
        ],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "streets",
        [
          feature_message([0, 12], 2, line_commands([line_segment(0, 12, 4, 12)]), 14),
          feature_message([0, 13], 2, line_commands([line_segment(0, 13, 4, 13)]), 15),
          feature_message([0, 14], 2, line_commands([line_segment(0, 14, 4, 14)]), 16),
          feature_message([0, 15], 2, line_commands([line_segment(0, 15, 4, 15)]), 17),
          feature_message([0, 16], 2, line_commands([line_segment(0, 16, 4, 16)]), 18),
          feature_message([0, 17], 2, line_commands([line_segment(0, 17, 4, 17)]), 19),
          feature_message([0, 18], 2, line_commands([line_segment(0, 18, 4, 18)]), 20),
          feature_message([0, 19], 2, line_commands([line_segment(0, 19, 4, 19)]), 21),
          feature_message([0, 19, 1, 20], 2, line_commands([line_segment(0, 20, 4, 20)]), 22),
          feature_message([0, 19, 2, 21], 2, line_commands([line_segment(0, 21, 4, 21)]), 23)
        ],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "buildings",
        [feature_message([], 3, polygon_commands([square(0, 24, 2)]), 24)],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "bridges",
        [feature_message([], 3, polygon_commands([square(3, 24, 2)]), 25)],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "boundaries",
        [feature_message([], 2, line_commands([line_segment(6, 24, 10, 24)]), 26)],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "pier_polygons",
        [feature_message([], 3, polygon_commands([square(12, 24, 2)]), 27)],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "pier_lines",
        [feature_message([], 2, line_commands([line_segment(15, 24, 19, 24)]), 28)],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "ferries",
        [feature_message([], 2, line_commands([line_segment(0, 27, 4, 27)]), 29)],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "aerialways",
        [feature_message([], 2, line_commands([line_segment(0, 28, 4, 28)]), 30)],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "mystery_polygons",
        [feature_message([], 3, polygon_commands([square(6, 27, 2)]), 31)],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "mystery_lines",
        [feature_message([], 2, line_commands([line_segment(9, 27, 13, 27)]), 32)],
        keys,
        values,
        32,
        2
      ),
      layer_message(
        "mystery_points",
        [feature_message([], 1, point_commands([{16, 28}]), 33)],
        keys,
        values,
        32,
        2
      )
    ])
  end

  defp square(x, y, size), do: [{x, y}, {x + size, y}, {x + size, y + size}, {x, y + size}]
  defp line_segment(x1, y1, x2, y2), do: [{x1, y1}, {x2, y2}]

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
