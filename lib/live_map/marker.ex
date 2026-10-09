defmodule LiveMap.Marker do
  @moduledoc false

  alias LiveMap.Coordinate
  alias LiveMap.Tile

  # The shortest step between two points of a shape, in pixels.
  @min_step 0.5

  def project(marker_slot, map_id, zoom, origin_x, origin_y, index, map_longitude) do
    {latitude, raw_longitude} = marker_position(marker_slot)
    k = round((map_longitude - raw_longitude) / 360.0)
    longitude = raw_longitude + k * 360.0

    id = normalize_id(Map.get(marker_slot, :id))
    title = marker_title(marker_slot)
    x = Float.round(Tile.x(longitude, zoom) * 256 - origin_x, 2)
    y = Float.round(Tile.y(latitude, zoom) * 256 - origin_y, 2)

    %{
      id: id,
      dom_id: dom_id(map_id, id, index),
      title: title,
      label: title,
      has_body: Map.get(marker_slot, :inner_block) != nil,
      latitude: latitude,
      longitude: longitude,
      x: x,
      y: y,
      scale: 1.0,
      slot: marker_slot
    }
  end

  def project_shape(type, shape_slot, map_id, zoom, origin_x, origin_y, index, map_longitude)
      when type in [:polygon, :polyline] do
    id = normalize_id(Map.get(shape_slot, :id))
    label = Map.get(shape_slot, :label)

    points =
      project_points(Map.fetch!(shape_slot, :points), zoom, origin_x, origin_y, map_longitude)

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

  defp marker_position(%{position: position}) when not is_nil(position) do
    Coordinate.parse_pair(position, :position)
  end

  defp marker_position(marker_slot) do
    case {Map.get(marker_slot, :latitude), Map.get(marker_slot, :longitude)} do
      {nil, nil} ->
        raise ArgumentError,
              "marker requires position; latitude and longitude are deprecated fallbacks"

      {latitude, longitude} when not is_nil(latitude) and not is_nil(longitude) ->
        {
          Coordinate.parse_number(latitude, :position),
          Coordinate.parse_number(longitude, :position)
        }

      _partial ->
        raise ArgumentError,
              "marker latitude and longitude must both be provided when position is omitted"
    end
  end

  defp marker_title(%{title: title}) when not is_nil(title), do: title
  defp marker_title(%{label: label}) when not is_nil(label), do: label

  defp marker_title(_marker_slot) do
    raise ArgumentError, "marker requires title; label is a deprecated fallback"
  end

  defp project_points(points, zoom, origin_x, origin_y, map_longitude) do
    points
    |> Enum.reduce({[], 0, nil}, fn point, {acc, longitude_offset, prev_lon} ->
      latitude = Coordinate.parse_number(Map.fetch!(point, :latitude), :shape)
      raw_longitude = Coordinate.parse_number(Map.fetch!(point, :longitude), :shape)

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
    |> shift_points_to_map_center(zoom, origin_x, origin_y, map_longitude)
  end

  defp shift_points_to_map_center([], _zoom, _origin_x, _origin_y, _map_longitude), do: []

  defp shift_points_to_map_center(points, zoom, origin_x, origin_y, map_longitude) do
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

    points
    |> Enum.map(fn {latitude, lon} ->
      final_lon = lon + global_offset
      x = Float.round(Tile.x(final_lon, zoom) * 256 - origin_x, 2)
      y = Float.round(Tile.y(latitude, zoom) * 256 - origin_y, 2)
      {x, y}
    end)
    |> thin()
  end

  # The points of a shape with no point nearer than @min_step pixels to
  # the point before it: such a point changes nothing on the screen. A
  # long line at a low zoom has many of them. The last point stays, so
  # the line ends at its end.
  defp thin([first | rest]) do
    {kept, skipped} =
      Enum.reduce(rest, {[first], nil}, fn {x, y} = point, {[{last_x, last_y} | _] = kept, _} ->
        if abs(x - last_x) < @min_step and abs(y - last_y) < @min_step,
          do: {kept, point},
          else: {[point | kept], nil}
      end)

    Enum.reverse(if skipped, do: [skipped | kept], else: kept)
  end

  defp points_attribute(points) do
    Enum.map_join(points, " ", fn {x, y} -> "#{x},#{y}" end)
  end
end
