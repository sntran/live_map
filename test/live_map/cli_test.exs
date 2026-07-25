defmodule LiveMap.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    server = LiveMap.TestTileServer.start_link()

    on_exit(fn ->
      LiveMap.TestTileServer.stop(server)
    end)

    %{server: server}
  end

  test "infers MVT output from the tile URL and forwards a custom user-agent", %{server: server} do
    LiveMap.TestTileServer.put_responses(server, "/0/0/0.mvt", [
      {200, [{"cache-control", "max-age=60"}], shortbread_tile()}
    ])

    output =
      capture_io(fn ->
        LiveMap.CLI.main([
          "--latitude",
          "0",
          "--longitude",
          "0",
          "--zoom",
          "0",
          "--width",
          "256",
          "--height",
          "256",
          "--tile-url",
          server.base_url <> "/{z}/{x}/{y}.mvt",
          "--tile-user-agent",
          "LiveMapCLI/1.0 (cli@example.com)"
        ])
      end)

    assert output =~ ~s(data-live-map-tile-state="ready")
    refute output =~ "<image"

    [request_headers | _rest] = LiveMap.TestTileServer.request_headers(server, "/0/0/0.mvt")
    assert {"user-agent", "LiveMapCLI/1.0 (cli@example.com)"} in request_headers
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
