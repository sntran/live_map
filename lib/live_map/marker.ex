defmodule LiveMap.Marker do
  @moduledoc false

  alias LiveMap.Tile

  def project(marker_slot, map_id, zoom, min_x, min_y, index, map_longitude) do
    latitude = parse_float(marker_slot.latitude)
    raw_longitude = parse_float(marker_slot.longitude)
    k = round((map_longitude - raw_longitude) / 360.0)
    longitude = raw_longitude + k * 360.0

    id = normalize_id(Map.get(marker_slot, :id))
    label = marker_slot.label
    x = Float.round(Tile.x(longitude, zoom) * 256 - min_x, 2)
    y = Float.round(Tile.y(latitude, zoom) * 256 - min_y, 2)

    %{
      id: id,
      dom_id: dom_id(map_id, id, index),
      label: label,
      has_body: Map.get(marker_slot, :inner_block) != nil,
      latitude: latitude,
      longitude: longitude,
      x: x,
      y: y,
      scale: 1.0,
      slot: marker_slot
    }
  end

  def project_shape(type, shape_slot, map_id, zoom, min_x, min_y, index, map_longitude) when type in [:polygon, :polyline] do
    id = normalize_id(Map.get(shape_slot, :id))
    label = Map.get(shape_slot, :label)
    points = project_points(Map.fetch!(shape_slot, :points), zoom, min_x, min_y, map_longitude)

    %{
      type: type,
      id: id,
      dom_id: shape_dom_id(type, map_id, id, index),
      label: label,
      points: points,
      points_attribute: points_attribute(points),
      class: Map.get(shape_slot, :class),
      style: Map.get(shape_slot, :style),
      fill: Map.get(shape_slot, :fill),
      stroke: Map.get(shape_slot, :stroke),
      stroke_width: Map.get(shape_slot, :"stroke-width")
    }
  end

  defp dom_id(map_id, nil, index), do: "#{map_id}-marker-#{index}"
  defp dom_id(map_id, id, _index), do: "#{map_id}-marker-#{id}"

  defp shape_dom_id(type, map_id, nil, index), do: "#{map_id}-#{type}-#{index}"
  defp shape_dom_id(type, map_id, id, _index), do: "#{map_id}-#{type}-#{id}"

  defp normalize_id(nil), do: nil
  defp normalize_id(id), do: to_string(id)

  defp project_points(points, zoom, min_x, min_y, map_longitude) do
    points
    |> Enum.reduce({[], 0, nil}, fn point, {acc, longitude_offset, prev_lon} ->
      latitude = parse_float(Map.fetch!(point, :latitude))
      raw_longitude = parse_float(Map.fetch!(point, :longitude))

      {new_offset, prev_lon} =
        case prev_lon do
          nil ->
            {longitude_offset, raw_longitude}

          prev ->
            delta = raw_longitude - prev

            new_offset =
              cond do
                delta > 180 -> longitude_offset - 360
                delta < -180 -> longitude_offset + 360
                true -> longitude_offset
              end

            {new_offset, raw_longitude}
        end

      normalized_lon = raw_longitude + new_offset

      {[{latitude, normalized_lon} | acc], new_offset, prev_lon}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> shift_points_to_map_center(zoom, min_x, min_y, map_longitude)
  end

  defp shift_points_to_map_center([], _zoom, _min_x, _min_y, _map_longitude), do: []

  defp shift_points_to_map_center(points, zoom, min_x, min_y, map_longitude) do
    {min_lon, max_lon} =
      Enum.reduce(points, {nil, nil}, fn {_, lon}, {min, max} ->
        {
          if(min, do: min(min, lon), else: lon),
          if(max, do: max(max, lon), else: lon)
        }
      end)

    center_lon = (min_lon + max_lon) / 2.0
    k = round((map_longitude - center_lon) / 360.0)
    global_offset = k * 360.0

    Enum.map(points, fn {latitude, lon} ->
      final_lon = lon + global_offset
      x = Float.round(Tile.x(final_lon, zoom) * 256 - min_x, 2)
      y = Float.round(Tile.y(latitude, zoom) * 256 - min_y, 2)
      {x, y}
    end)
  end

  defp points_attribute(points) do
    Enum.map_join(points, " ", fn {x, y} -> "#{x},#{y}" end)
  end

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value / 1

  defp parse_float(value) do
    case Float.parse(to_string(value)) do
      {parsed, _rest} -> parsed
      :error -> raise ArgumentError, "invalid marker coordinate: #{inspect(value)}"
    end
  end
end
