defmodule LiveMap.MVT do
  @moduledoc false

  import Bitwise

  @type decode_error :: term()

  @doc """
  Decodes a Mapbox Vector Tile into a tile-local SVG document.
  """
  @spec decode(binary(), keyword()) :: {:ok, Phoenix.HTML.safe()} | {:error, decode_error()}
  def decode(binary, opts \\ []) when is_binary(binary) do
    with {:ok, normalized_binary} <- maybe_gunzip(binary),
         {:ok, layers} <- parse_tile(normalized_binary),
         {:ok, svg} <- render_svg(layers, normalized_binary, opts),
         :ok <- validate_iodata(svg) do
      try do
        {:ok, Phoenix.HTML.raw(svg)}
      rescue
        error ->
          {:error,
           {:decode_exception, Exception.message(error),
            inspect(svg, printable_limit: :infinity, limit: :infinity)}}
      end
    else
      {:error, _reason} = error -> error
    end
  rescue
    error ->
      {:error,
       {:decode_exception, Exception.message(error), Exception.format_stacktrace(__STACKTRACE__)}}
  end

  defp maybe_gunzip(<<0x1F, 0x8B, 0x08, _rest::binary>> = compressed) do
    {:ok, :zlib.gunzip(compressed)}
  rescue
    _error -> {:error, :invalid_gzip}
  end

  defp maybe_gunzip(binary), do: {:ok, binary}

  defp parse_tile(binary) do
    with {:ok, fields} <- parse_message(binary) do
      fields
      |> Enum.filter(fn {field_number, wire_type, _value} ->
        field_number == 3 and wire_type == 2
      end)
      |> Task.async_stream(fn {_field_number, _wire_type, layer_binary} -> parse_layer(layer_binary) end, ordered: true, timeout: :infinity)
      |> Enum.map(fn {:ok, result} -> result end)
      |> collect_results()
    end
  end

  defp parse_layer(binary) do
    with {:ok, fields} <- parse_message(binary),
         {:ok, name} <- required_string(fields, 1, :missing_layer_name),
         {:ok, version} <- required_varint(fields, 15, :missing_layer_version),
         :ok <- validate_layer_version(version),
         {:ok, keys} <- parse_strings(fields, 3),
         {:ok, values} <- parse_values(fields, 4),
         extent <- optional_varint(fields, 5, 4096),
         {:ok, features} <- parse_features(fields, name, keys, values, extent) do
      {:ok, %{name: name, extent: extent, features: features}}
    end
  end

  defp parse_features(fields, layer_name, keys, values, extent) do
    fields
    |> Enum.filter(fn {field_number, wire_type, _value} ->
      field_number == 2 and wire_type == 2
    end)
    |> Enum.map(fn {_field_number, _wire_type, feature_binary} ->
      parse_feature(feature_binary, layer_name, keys, values, extent)
    end)
    |> collect_results()
  end

  defp parse_feature(binary, layer_name, keys, values, extent) do
    with {:ok, fields} <- parse_message(binary),
         {:ok, geometry_type} <- parse_geometry_type(optional_varint(fields, 3, nil)),
         {:ok, tags} <- packed_varints(fields, 2),
         {:ok, geometry_binary} <- extract_packed_binary(fields, 4),
         {:ok, properties} <- decode_tags(tags, keys, values),
         {:ok, geometry} <- decode_geometry(geometry_type, geometry_binary) do
      {:ok,
       %{
         id: optional_varint(fields, 1, nil),
         layer: layer_name,
         extent: extent,
         type: geometry_type,
         geometry: geometry,
         properties: properties
       }}
    end
  end

  defp decode_tags(tags, keys, values) do
    if rem(length(tags), 2) != 0 do
      {:error, :odd_number_of_tags}
    else
      tags
      |> Enum.chunk_every(2)
      |> Enum.reduce_while({:ok, %{}}, fn [key_index, value_index], {:ok, properties} ->
        with {:ok, key} <- indexed_value(keys, key_index, :invalid_key_index),
             {:ok, value} <- indexed_value(values, value_index, :invalid_value_index) do
          {:cont, {:ok, Map.put(properties, key, value)}}
        else
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp extract_packed_binary(fields, field_number) do
    fields
    |> Enum.reduce_while({:ok, []}, fn
      {number, 2, packed_binary}, {:ok, acc} when number == field_number ->
        {:cont, {:ok, [packed_binary | acc]}}
      {number, 0, value}, {:ok, acc} when number == field_number ->
        {:cont, {:ok, [encode_varint(value) | acc]}}
      _other, acc ->
        {:cont, acc}
    end)
    |> case do
      {:ok, iodata} -> {:ok, iodata |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, _} = error -> error
    end
  end

  defp encode_varint(value) when value < 128, do: <<value>>
  defp encode_varint(value), do: <<(band(value, 127) ||| 128), encode_varint(value >>> 7)::binary>>

  defp decode_geometry(:point, commands), do: decode_points(commands, 0, 0, [])
  defp decode_geometry(:line, commands), do: decode_line_parts(commands, 0, 0, [], [])
  defp decode_geometry(:polygon, commands), do: decode_polygon_rings(commands, 0, 0, [], [])

  defp decode_points(<<>>, _x, _y, points), do: {:ok, Enum.reverse(points)}

  defp decode_points(commands, x, y, points) do
    with {:ok, {command_id, count}, rest} <- next_command(commands),
         {:ok, next_x, next_y, next_points, remaining} <-
           read_coordinates(rest, count, x, y, points) do
      if command_id == 1 do
        decode_points(remaining, next_x, next_y, next_points)
      else
        {:error, {:illegal_command, command_id, :point}}
      end
    else
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_point_geometry}
    end
  end

  defp decode_line_parts(<<>>, _x, _y, [], parts), do: {:ok, Enum.reverse(parts)}

  defp decode_line_parts(<<>>, _x, _y, current_part, parts) do
    finalize_line_part(current_part, parts)
  end

  defp decode_line_parts(commands, x, y, current_part, parts) do
    with {:ok, {command_id, count}, rest} <- next_command(commands) do
      case command_id do
        1 ->
          with {:ok, next_parts} <- finalize_open_line_part(current_part, parts),
               {:ok, next_x, next_y, next_points, remaining} <-
                 read_coordinates(rest, count, x, y, []) do
            if length(next_points) == 1 do
              decode_line_parts(remaining, next_x, next_y, Enum.reverse(next_points), next_parts)
            else
              {:error, :invalid_linestring_moveto_count}
            end
          end

        2 ->
          if current_part == [] do
            {:error, :lineto_without_moveto}
          else
            with {:ok, next_x, next_y, next_points, remaining} <-
                   read_coordinates(rest, count, x, y, Enum.reverse(current_part)) do
              decode_line_parts(remaining, next_x, next_y, Enum.reverse(next_points), parts)
            end
          end

        other ->
          {:error, {:illegal_command, other, :line}}
      end
    end
  end

  defp decode_polygon_rings(<<>>, _x, _y, [], rings), do: {:ok, Enum.reverse(rings)}

  defp decode_polygon_rings(<<>>, _x, _y, _current_ring, _rings),
    do: {:error, :unterminated_polygon_ring}

  defp decode_polygon_rings(commands, x, y, current_ring, rings) do
    with {:ok, {command_id, count}, rest} <- next_command(commands) do
      case command_id do
        1 ->
          if current_ring != [] do
            {:error, :moveto_before_closepath}
          else
            with {:ok, next_x, next_y, next_points, remaining} <-
                   read_coordinates(rest, count, x, y, []) do
              if length(next_points) == 1 do
                decode_polygon_rings(remaining, next_x, next_y, Enum.reverse(next_points), rings)
              else
                {:error, :invalid_polygon_moveto_count}
              end
            end
          end

        2 ->
          if current_ring == [] do
            {:error, :lineto_without_moveto}
          else
            with {:ok, next_x, next_y, next_points, remaining} <-
                   read_coordinates(rest, count, x, y, Enum.reverse(current_ring)) do
              decode_polygon_rings(remaining, next_x, next_y, Enum.reverse(next_points), rings)
            end
          end

        7 ->
          if count != 1 do
            {:error, :invalid_closepath_count}
          else
            finalize_polygon_ring(current_ring, rings, rest, x, y)
          end

        other ->
          {:error, {:illegal_command, other, :polygon}}
      end
    end
  end

  defp finalize_polygon_ring(current_ring, rings, rest, x, y) do
    cond do
      length(current_ring) < 3 ->
        {:error, :polygon_ring_too_short}

      ring_area(current_ring) == 0 ->
        {:error, :degenerate_polygon_ring}

      true ->
        decode_polygon_rings(rest, x, y, [], [current_ring | rings])
    end
  end

  defp finalize_open_line_part([], parts), do: {:ok, parts}

  defp finalize_open_line_part(current_part, parts) do
    finalize_line_part(current_part, parts)
  end

  defp finalize_line_part(current_part, _parts) when length(current_part) < 2 do
    {:error, :linestring_too_short}
  end

  defp finalize_line_part(current_part, parts) do
    {:ok, [current_part | parts]}
  end

  defp read_coordinates(commands, 0, x, y, points), do: {:ok, x, y, points, commands}

  defp read_coordinates(commands, count, x, y, points) when count > 0 do
    with {:ok, delta_x, rest} <- next_coordinate(commands),
         {:ok, delta_y, remaining} <- next_coordinate(rest) do
      next_x = x + delta_x
      next_y = y + delta_y
      read_coordinates(remaining, count - 1, next_x, next_y, [{next_x, next_y} | points])
    end
  end

  defp next_command(commands) do
    with {:ok, command_integer, rest} <- next_integer(commands) do
      command_id = band(command_integer, 0x7)
      count = command_integer >>> 3

      if count > 0 do
        {:ok, {command_id, count}, rest}
      else
        {:error, :invalid_command_count}
      end
    end
  end

  defp next_coordinate(commands) do
    with {:ok, value, rest} <- next_integer(commands) do
      {:ok, zigzag_decode(value), rest}
    end
  end

  defp next_integer(<<>>), do: {:error, :truncated_geometry}
  defp next_integer(binary), do: parse_varint(binary)

  defp parse_geometry_type(1), do: {:ok, :point}
  defp parse_geometry_type(2), do: {:ok, :line}
  defp parse_geometry_type(3), do: {:ok, :polygon}
  defp parse_geometry_type(nil), do: {:error, :missing_geometry_type}
  defp parse_geometry_type(type), do: {:error, {:unsupported_geometry_type, type}}

  defp parse_values(fields, field_number) do
    fields
    |> Enum.filter(fn {number, wire_type, _value} ->
      number == field_number and wire_type == 2
    end)
    |> Enum.map(fn {_number, _wire_type, value_binary} -> parse_value(value_binary) end)
    |> collect_results()
  end

  defp parse_value(binary) do
    with {:ok, fields} <- parse_message(binary) do
      case fields do
        [{1, 2, value}] -> {:ok, value}
        [{2, 5, value}] -> {:ok, value}
        [{3, 1, value}] -> {:ok, value}
        [{4, 0, value}] -> {:ok, value}
        [{5, 0, value}] -> {:ok, value}
        [{6, 0, value}] -> {:ok, zigzag_decode(value)}
        [{7, 0, value}] when value in [0, 1] -> {:ok, value == 1}
        [] -> {:error, :empty_value_message}
        _other -> {:error, :unsupported_value_encoding}
      end
    end
  end

  defp parse_strings(fields, field_number) do
    fields
    |> Enum.filter(fn {number, wire_type, _value} ->
      number == field_number and wire_type == 2
    end)
    |> Enum.reduce_while({:ok, []}, fn {_number, _wire_type, value}, {:ok, strings} ->
      if is_binary(value) do
        {:cont, {:ok, [value | strings]}}
      else
        {:halt, {:error, {:expected_string, field_number}}}
      end
    end)
    |> case do
      {:ok, strings} -> {:ok, Enum.reverse(strings)}
      {:error, _reason} = error -> error
    end
  end

  defp packed_varints(fields, field_number) do
    fields
    |> Enum.filter(fn {number, _wire_type, _value} -> number == field_number end)
    |> Enum.reduce_while({:ok, []}, fn
      {_number, 0, value}, {:ok, values} when is_integer(value) ->
        {:cont, {:ok, values ++ [value]}}

      {_number, 2, packed_binary}, {:ok, values} when is_binary(packed_binary) ->
        case decode_packed_varints(packed_binary) do
          {:ok, packed_values} -> {:cont, {:ok, values ++ packed_values}}
          {:error, _reason} = error -> {:halt, error}
        end

      {_number, _wire_type, _value}, _acc ->
        {:halt, {:error, {:unsupported_packed_field, field_number}}}
    end)
  end

  defp decode_packed_varints(binary), do: decode_packed_varints(binary, [])
  defp decode_packed_varints(<<>>, values), do: {:ok, Enum.reverse(values)}

  defp decode_packed_varints(binary, values) do
    with {:ok, value, rest} <- parse_varint(binary) do
      decode_packed_varints(rest, [value | values])
    end
  end

  defp required_string(fields, field_number, error_reason) do
    case Enum.find(fields, fn {number, wire_type, _value} ->
           number == field_number and wire_type == 2
         end) do
      {^field_number, 2, value} when is_binary(value) -> {:ok, value}
      nil -> {:error, error_reason}
      _other -> {:error, {:expected_string, field_number}}
    end
  end

  defp required_varint(fields, field_number, error_reason) do
    case Enum.find(fields, fn {number, wire_type, _value} ->
           number == field_number and wire_type == 0
         end) do
      {^field_number, 0, value} when is_integer(value) -> {:ok, value}
      nil -> {:error, error_reason}
      _other -> {:error, {:expected_varint, field_number}}
    end
  end

  defp optional_varint(fields, field_number, default) do
    case Enum.find(fields, fn {number, wire_type, _value} ->
           number == field_number and wire_type == 0
         end) do
      {^field_number, 0, value} when is_integer(value) -> value
      _other -> default
    end
  end

  defp validate_layer_version(2), do: :ok
  defp validate_layer_version(version), do: {:error, {:unsupported_layer_version, version}}

  defp indexed_value(values, index, error_reason) when is_integer(index) and index >= 0 do
    case Enum.at(values, index) do
      nil -> {:error, error_reason}
      value -> {:ok, value}
    end
  end

  defp indexed_value(_values, _index, error_reason), do: {:error, error_reason}

  defp parse_message(binary), do: parse_message(binary, [])
  defp parse_message(<<>>, fields), do: {:ok, Enum.reverse(fields)}

  defp parse_message(binary, fields) do
    with {:ok, key, rest} <- parse_varint(binary),
         field_number when field_number > 0 <- key >>> 3,
         wire_type <- band(key, 0x7),
         {:ok, value, remaining} <- parse_field_value(wire_type, rest) do
      parse_message(remaining, [{field_number, wire_type, value} | fields])
    else
      0 -> {:error, :invalid_field_number}
      {:error, _reason} = error -> error
    end
  end

  defp parse_field_value(0, binary), do: parse_varint(binary)

  defp parse_field_value(1, <<value::little-float-size(64), rest::binary>>) do
    {:ok, value, rest}
  end

  defp parse_field_value(1, _binary), do: {:error, :truncated_fixed64}

  defp parse_field_value(2, binary) do
    with {:ok, length, rest} <- parse_varint(binary),
         true <- byte_size(rest) >= length || {:error, :truncated_length_delimited},
         <<value::binary-size(^length), remaining::binary>> <- rest do
      {:ok, value, remaining}
    else
      {:error, _reason} = error -> error
      _other -> {:error, :truncated_length_delimited}
    end
  end

  defp parse_field_value(5, <<value::little-float-size(32), rest::binary>>) do
    {:ok, value, rest}
  end

  defp parse_field_value(5, _binary), do: {:error, :truncated_fixed32}
  defp parse_field_value(wire_type, _binary), do: {:error, {:unsupported_wire_type, wire_type}}

  defp parse_varint(<<0::1, v1::7, rest::binary>>), do: {:ok, v1, rest}

  defp parse_varint(<<1::1, v1::7, 0::1, v2::7, rest::binary>>) do
    {:ok, v1 ||| (v2 <<< 7), rest}
  end

  defp parse_varint(<<1::1, v1::7, 1::1, v2::7, 0::1, v3::7, rest::binary>>) do
    {:ok, v1 ||| (v2 <<< 7) ||| (v3 <<< 14), rest}
  end

  defp parse_varint(<<1::1, v1::7, 1::1, v2::7, 1::1, v3::7, 0::1, v4::7, rest::binary>>) do
    {:ok, v1 ||| (v2 <<< 7) ||| (v3 <<< 14) ||| (v4 <<< 21), rest}
  end

  defp parse_varint(<<1::1, v1::7, 1::1, v2::7, 1::1, v3::7, 1::1, v4::7, 0::1, v5::7, rest::binary>>) do
    {:ok, v1 ||| (v2 <<< 7) ||| (v3 <<< 14) ||| (v4 <<< 21) ||| (v5 <<< 28), rest}
  end

  defp parse_varint(binary) do
    parse_varint_slow(binary, 0, 0)
  end

  defp parse_varint_slow(<<>>, _shift, _value), do: {:error, :truncated_varint}

  defp parse_varint_slow(_binary, shift, _value) when shift >= 70 do
    {:error, :varint_overflow}
  end

  defp parse_varint_slow(<<0::1, v::7, rest::binary>>, shift, value) do
    {:ok, value ||| (v <<< shift), rest}
  end

  defp parse_varint_slow(<<1::1, v::7, rest::binary>>, shift, value) do
    parse_varint_slow(rest, shift + 7, value ||| (v <<< shift))
  end

  defp collect_results(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, _reason} = error, _acc -> {:halt, error}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, _reason} = error -> error
    end
  end

  defp zigzag_decode(value) when is_integer(value) do
    bxor(value >>> 1, -(value &&& 1))
  end

  defp render_svg(layers, binary, opts) do
    hash = short_hash(binary)
    id_prefix = Keyword.get(opts, :id_prefix, hash)
    custom_css = Keyword.get(opts, :custom_css, "")
    clip_id = "live-map-mvt-clip-#{id_prefix}"
    css = tile_css() <> "\n" <> custom_css

    groups =
      layers
      |> Enum.flat_map(& &1.features)
      |> Enum.reduce(%{}, &group_feature/2)
      |> Enum.sort_by(fn {key, _value} -> key end)

    rendered_paths =
      groups
      |> Enum.map(fn {key, group} -> render_group(key, group) end)
      |> Enum.reject(&is_nil/1)

    {:ok,
     [
       "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1 1\" preserveAspectRatio=\"none\" overflow=\"hidden\" class=\"live-map-tile-svg\" data-live-map-tile-format=\"mvt\">",
       "<defs><clipPath id=\"",
       clip_id,
       "\"><rect x=\"0\" y=\"0\" width=\"1\" height=\"1\"/></clipPath></defs>",
       "<style>",
       css,
       "</style>",
       "<g clip-path=\"url(#",
       clip_id,
       ")\">",
       rendered_paths,
       "</g></svg>"
     ]}
  end

  defp group_feature(feature, groups) do
    role = feature_role(feature.layer, feature.properties)
    kind = feature_kind(feature.properties)
    bridge? = truthy?(Map.get(feature.properties, "bridge"))
    tunnel? = truthy?(Map.get(feature.properties, "tunnel"))
    group_key = {role, feature.type, kind, bridge?, tunnel?, feature.layer}
    contribution = geometry_contribution(feature)

    Map.update(groups, group_key, contribution, &merge_group_geometry(&1, contribution))
  end

  defp geometry_contribution(%{type: :point, geometry: points, extent: extent} = feature) do
    name = Map.get(feature.properties, "name:en") || Map.get(feature.properties, "name")

    if name do
      %{named_points: Enum.map(points, &{name, normalize_point(&1, extent)})}
    else
      %{points: Enum.map(points, &normalize_point(&1, extent))}
    end
  end

  defp geometry_contribution(%{type: :line, geometry: parts, extent: extent}) do
    %{paths: Enum.map(parts, &path_segment(&1, extent, false))}
  end

  defp geometry_contribution(%{type: :polygon, geometry: rings, extent: extent}) do
    %{paths: Enum.map(rings, &path_segment(&1, extent, true))}
  end

  defp merge_group_geometry(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value -> left_value ++ right_value end)
  end

  defp normalize_point({x, y}, extent) do
    {normalize_coordinate(x, extent), normalize_coordinate(y, extent)}
  end

  defp path_segment(points, extent, close?) do
    [first | rest] = Enum.map(points, &normalize_point(&1, extent))

    [
      "M",
      coordinate_pair(first),
      Enum.map(rest, fn point -> ["L", coordinate_pair(point)] end),
      if(close?, do: "Z", else: [])
    ]
  end

  defp render_group({_role, geometry_type, _kind, _bridge?, _tunnel?, _layer} = key, group) do
    points = Map.get(group, :points, [])
    named_points = Map.get(group, :named_points, [])
    paths = Map.get(group, :paths, [])

    rendered_points =
      if points != [] do
        render_path(key, Enum.map(points, &point_path/1), :point)
      end

    rendered_named =
      if named_points != [] do
        render_texts(key, named_points)
      end

    rendered_paths =
      if paths != [] do
        render_path(key, paths, geometry_type)
      end

    [rendered_points, rendered_named, rendered_paths] |> Enum.reject(&is_nil/1)
  end

  defp render_path({role, _geometry_type, kind, bridge?, tunnel?, layer}, path_data, shape) do
    classes =
      [
        "live-map-shortbread-feature",
        "live-map-shortbread-role-#{css_token(role)}",
        "live-map-shortbread-shape-#{css_token(shape)}",
        "live-map-shortbread-layer-#{css_token(layer)}",
        "live-map-shortbread-kind-#{css_token(kind)}",
        if(bridge?, do: "live-map-shortbread-bridge", else: nil),
        if(tunnel?, do: "live-map-shortbread-tunnel", else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    [
      "<path class=\"",
      classes,
      "\" d=\"",
      path_data,
      "\"",
      if(shape == :polygon, do: " fill-rule=\"evenodd\"", else: []),
      if(bridge?, do: " data-live-map-bridge", else: ""),
      if(tunnel?, do: " data-live-map-tunnel", else: ""),
      " />"
    ]
  end

  defp render_texts({role, _geometry_type, kind, bridge?, tunnel?, layer}, named_points) do
    classes =
      [
        "live-map-shortbread-feature",
        "live-map-shortbread-role-#{css_token(role)}",
        "live-map-shortbread-shape-text",
        "live-map-shortbread-layer-#{css_token(layer)}",
        "live-map-shortbread-kind-#{css_token(kind)}",
        if(bridge?, do: "live-map-shortbread-bridge", else: nil),
        if(tunnel?, do: "live-map-shortbread-tunnel", else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    Enum.map(named_points, fn {name, {x, y}} ->
      [
        "<text class=\"",
        classes,
        "\" x=\"",
        to_string(x),
        "\" y=\"",
        to_string(y),
        "\">",
        escape_text(name),
        "</text>"
      ]
    end)
  end

  defp escape_text(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # CSS rules embedded inside each tile SVG document so they apply within the
  # SVG <use> shadow DOM. Unlike the outer <style>, rules here resolve against
  # the tile's own document scope. CSS custom properties (--live-map-*) defined
  # on ancestor elements still inherit through, so user overrides still work.
  @tile_css_content """
  .live-map-shortbread-shape-line { fill: none; }
  .live-map-shortbread-shape-text {
    fill: var(--live-map-text-fill, #333);
    font-family: var(--live-map-text-font-family, sans-serif);
    font-size: var(--live-map-text-font-size, 0.04px);
    text-anchor: var(--live-map-text-anchor, middle);
    dominant-baseline: var(--live-map-text-dominant-baseline, central);
    paint-order: stroke;
    stroke: var(--live-map-text-stroke, #fff);
    stroke-width: var(--live-map-text-stroke-width, 0.01px);
    pointer-events: none;
  }
  .live-map-shortbread-feature { stroke-linecap: round; stroke-linejoin: round; }
  .live-map-shortbread-shape-polygon { stroke: none; }

  .live-map-shortbread-role-water.live-map-shortbread-shape-polygon { fill: var(--live-map-water-polygon-fill, var(--live-map-water-fill, #9bd4f5)); stroke: var(--live-map-water-polygon-stroke, var(--live-map-water-stroke, none)); }
  .live-map-shortbread-role-water.live-map-shortbread-shape-line { stroke: var(--live-map-water-line-stroke, var(--live-map-water-stroke, #5aa7da)); stroke-width: var(--live-map-water-line-width, 0.0035); }
  .live-map-shortbread-role-water.live-map-shortbread-kind-river { stroke-width: var(--live-map-water-river-stroke-width, var(--live-map-water-line-width, 0.006)); }
  .live-map-shortbread-role-water.live-map-shortbread-kind-canal { stroke-width: var(--live-map-water-canal-stroke-width, var(--live-map-water-line-width, 0.0045)); }
  .live-map-shortbread-role-water.live-map-shortbread-kind-stream { stroke-width: var(--live-map-water-stream-stroke-width, var(--live-map-water-line-width, 0.003)); }

  .live-map-shortbread-role-land.live-map-shortbread-shape-polygon { fill: var(--live-map-land-fill, #d7e2c4); }
  .live-map-shortbread-role-land.live-map-shortbread-kind-forest { fill: var(--live-map-land-forest-fill, var(--live-map-land-fill, #bfd7b5)); }
  .live-map-shortbread-role-land.live-map-shortbread-kind-park { fill: var(--live-map-land-park-fill, var(--live-map-land-fill, #cbe3bc)); }
  .live-map-shortbread-role-land.live-map-shortbread-kind-grass { fill: var(--live-map-land-grass-fill, var(--live-map-land-fill, #cfe6bf)); }
  .live-map-shortbread-role-land.live-map-shortbread-kind-farmland { fill: var(--live-map-land-farmland-fill, var(--live-map-land-fill, #ded5ad)); }
  .live-map-shortbread-role-land.live-map-shortbread-kind-sand { fill: var(--live-map-land-sand-fill, var(--live-map-land-fill, #ead7a3)); }
  .live-map-shortbread-role-land.live-map-shortbread-kind-beach { fill: var(--live-map-land-beach-fill, var(--live-map-land-fill, #f0ddb0)); }

  .live-map-shortbread-role-site.live-map-shortbread-shape-polygon { fill: var(--live-map-site-polygon-fill, var(--live-map-site-fill, #efe7d3)); opacity: var(--live-map-site-polygon-opacity, 0.75); }
  .live-map-shortbread-role-site.live-map-shortbread-shape-point { fill: var(--live-map-site-point-fill, var(--live-map-site-fill, #8f7248)); stroke: none; }

  .live-map-shortbread-role-building.live-map-shortbread-shape-polygon { fill: var(--live-map-building-fill, #d8ccbe); stroke: var(--live-map-building-stroke, #b8a48f); stroke-width: var(--live-map-building-stroke-width, 0.0015); }

  .live-map-shortbread-role-street.live-map-shortbread-shape-line { stroke: var(--live-map-street-stroke, #f5f3ef); stroke-width: var(--live-map-street-stroke-width, 0.0045); }
  .live-map-shortbread-role-street.live-map-shortbread-kind-motorway { stroke: var(--live-map-street-motorway-stroke, var(--live-map-street-stroke, #f29b49)); stroke-width: var(--live-map-street-motorway-stroke-width, 0.012); }
  .live-map-shortbread-role-street.live-map-shortbread-kind-trunk { stroke: var(--live-map-street-trunk-stroke, var(--live-map-street-stroke, #e8b85f)); stroke-width: var(--live-map-street-trunk-stroke-width, 0.011); }
  .live-map-shortbread-role-street.live-map-shortbread-kind-primary { stroke: var(--live-map-street-primary-stroke, var(--live-map-street-stroke, #f2c56f)); stroke-width: var(--live-map-street-primary-stroke-width, 0.009); }
  .live-map-shortbread-role-street.live-map-shortbread-kind-secondary { stroke: var(--live-map-street-secondary-stroke, var(--live-map-street-stroke, #e6d286)); stroke-width: var(--live-map-street-secondary-stroke-width, 0.007); }
  .live-map-shortbread-role-street.live-map-shortbread-kind-tertiary { stroke: var(--live-map-street-tertiary-stroke, var(--live-map-street-stroke, #d8d4c8)); stroke-width: var(--live-map-street-tertiary-stroke-width, 0.006); }
  .live-map-shortbread-role-street.live-map-shortbread-kind-rail { stroke: var(--live-map-street-rail-stroke, var(--live-map-street-stroke, #7a6f66)); stroke-width: var(--live-map-street-rail-stroke-width, 0.004); }
  .live-map-shortbread-role-street.live-map-shortbread-kind-tram { stroke: var(--live-map-street-tram-stroke, var(--live-map-street-stroke, #8a7d73)); }
  .live-map-shortbread-role-street.live-map-shortbread-kind-subway { stroke-width: var(--live-map-street-subway-stroke-width, 0.003); }
  .live-map-shortbread-role-street.live-map-shortbread-shape-polygon { fill: var(--live-map-street-polygon-fill, var(--live-map-street-fill, #ece7df)); }
  .live-map-shortbread-role-street.live-map-shortbread-kind-runway { fill: var(--live-map-street-runway-fill, var(--live-map-street-fill, #d8d2c6)); }
  .live-map-shortbread-role-street.live-map-shortbread-kind-taxiway { fill: var(--live-map-street-taxiway-fill, var(--live-map-street-fill, #ddd7cc)); }

  .live-map-shortbread-role-bridge.live-map-shortbread-shape-polygon { fill: var(--live-map-bridge-fill, #d8d2c8); stroke: var(--live-map-bridge-stroke, #a89e91); stroke-width: var(--live-map-bridge-stroke-width, 0.0015); }

  .live-map-shortbread-role-boundary.live-map-shortbread-shape-line { stroke: var(--live-map-boundary-stroke, #70839a); stroke-width: var(--live-map-boundary-stroke-width, 0.002); stroke-dasharray: var(--live-map-boundary-stroke-dasharray, 0.01 0.008); }

  .live-map-shortbread-role-pier.live-map-shortbread-shape-polygon { fill: var(--live-map-pier-polygon-fill, var(--live-map-pier-fill, #bca994)); }
  .live-map-shortbread-role-pier.live-map-shortbread-shape-line { stroke: var(--live-map-pier-line-stroke, var(--live-map-pier-stroke, #8c7760)); stroke-width: var(--live-map-pier-line-width, 0.0035); }

  .live-map-shortbread-role-ferry.live-map-shortbread-shape-line { stroke: var(--live-map-ferry-stroke, #4b87b2); stroke-width: var(--live-map-ferry-stroke-width, 0.0025); stroke-dasharray: var(--live-map-ferry-stroke-dasharray, 0.01 0.008); }

  .live-map-shortbread-role-aerialway.live-map-shortbread-shape-line { stroke: var(--live-map-aerialway-stroke, #7a6b59); stroke-width: var(--live-map-aerialway-stroke-width, 0.002); stroke-dasharray: var(--live-map-aerialway-stroke-dasharray, 0.006 0.004); }

  .live-map-shortbread-role-other.live-map-shortbread-shape-point { fill: var(--live-map-other-point-fill, var(--live-map-other-fill, #7d6a4f)); stroke: none; }
  .live-map-shortbread-role-other.live-map-shortbread-shape-line { stroke: var(--live-map-other-line-stroke, var(--live-map-other-stroke, #738091)); stroke-width: var(--live-map-other-line-stroke-width, 0.0025); }
  .live-map-shortbread-role-other.live-map-shortbread-shape-polygon { fill: var(--live-map-other-polygon-fill, var(--live-map-other-fill, #dfe6ee)); }

  .live-map-shortbread-tunnel { opacity: var(--live-map-tunnel-opacity, 0.7); }
  """

  @tile_css String.trim(@tile_css_content)

  defp tile_css, do: @tile_css

  defp point_path({x, y}) do
    radius = 0.01

    [
      "M",
      format_number(x + radius),
      " ",
      format_number(y),
      "A",
      format_number(radius),
      " ",
      format_number(radius),
      " 0 1 0 ",
      format_number(x - radius),
      " ",
      format_number(y),
      "A",
      format_number(radius),
      " ",
      format_number(radius),
      " 0 1 0 ",
      format_number(x + radius),
      " ",
      format_number(y)
    ]
  end

  defp feature_role(layer_name, _properties)
       when layer_name in ["ocean", "water_polygons", "water_lines", "dam_lines", "dam_polygons"],
       do: "water"

  defp feature_role(layer_name, _properties) when layer_name == "land", do: "land"

  defp feature_role(layer_name, _properties)
       when layer_name in [
              "sites",
              "pois",
              "public_transport",
              "place_labels",
              "addresses",
              "water_polygons_labels",
              "water_lines_labels",
              "street_labels",
              "street_labels_points",
              "streets_polygons_labels"
            ],
       do: "site"

  defp feature_role(layer_name, _properties) when layer_name == "buildings", do: "building"

  defp feature_role(layer_name, _properties) when layer_name in ["streets", "street_polygons"],
    do: "street"

  defp feature_role(layer_name, _properties) when layer_name == "bridges", do: "bridge"

  defp feature_role(layer_name, _properties) when layer_name in ["boundaries", "boundary_labels"],
    do: "boundary"

  defp feature_role(layer_name, _properties) when layer_name in ["pier_lines", "pier_polygons"],
    do: "pier"

  defp feature_role(layer_name, _properties) when layer_name == "ferries", do: "ferry"
  defp feature_role(layer_name, _properties) when layer_name == "aerialways", do: "aerialway"
  defp feature_role(_layer_name, _properties), do: "other"

  defp feature_kind(properties) do
    properties
    |> Enum.find_value("default", fn {key, value} ->
      if key in [
           "kind",
           "amenity",
           "leisure",
           "tourism",
           "shop",
           "highway",
           "historic",
           "place",
           "man_made",
           "office"
         ] and is_binary(value) do
        value
      else
        nil
      end
    end)
  end

  defp normalize_coordinate(value, extent) do
    value / extent
  end

  defp coordinate_pair({x, y}) do
    [format_number(x), " ", format_number(y)]
  end

  defp format_number(number) when is_integer(number), do: Integer.to_string(number)

  defp format_number(number) when is_float(number) do
    if trunc(number) == number do
      Integer.to_string(trunc(number))
    else
      :erlang.float_to_binary(number, [{:decimals, 4}, :compact])
    end
  end

  defp ring_area(points) do
    points
    |> Enum.zip(Enum.drop(points, 1) ++ [hd(points)])
    |> Enum.reduce(0, fn {{x1, y1}, {x2, y2}}, area -> area + (x1 * y2 - x2 * y1) end)
  end

  defp truthy?(true), do: true
  defp truthy?(1), do: true
  defp truthy?("true"), do: true
  defp truthy?(_value), do: false

  defp css_token(value) when is_atom(value), do: css_token(Atom.to_string(value))

  defp css_token(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "default"
      token -> token
    end
  end

  defp short_hash(binary) do
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp validate_iodata(binary) when is_binary(binary), do: :ok

  defp validate_iodata(integer) when is_integer(integer) and integer >= 0 and integer <= 255,
    do: :ok

  defp validate_iodata([]), do: :ok

  defp validate_iodata([head | tail]) do
    with :ok <- validate_iodata(head),
         :ok <- validate_iodata(tail) do
      :ok
    end
  end

  defp validate_iodata(other), do: {:error, {:invalid_svg_iodata, other}}
end
