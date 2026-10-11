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

    [points | holes] =
      project_rings(
        [Map.fetch!(shape_slot, :points) | holes(type, shape_slot)],
        zoom,
        origin_x,
        origin_y,
        map_longitude
      )

    %{
      type: type,
      id: id,
      dom_id: shape_dom_id(type, map_id, id, index),
      label: label,
      points: points,
      points_attribute: points_attribute(points),
      holes: holes,
      path: path([points | holes]),
      group: normalize_id(Map.get(shape_slot, :group)),
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

  # Only a polygon has holes.
  defp holes(:polygon, shape_slot), do: Map.get(shape_slot, :holes) || []
  defp holes(:polyline, _shape_slot), do: []

  # The rings of a shape: its points, then its holes. The holes go to the
  # copy of the world of the points, and all the rings move with the
  # points to the copy of the world of the map. A hole with fewer than 3
  # points after `thin/1` has no area: it is not in the shape.
  defp project_rings([points | holes], zoom, origin_x, origin_y, map_longitude) do
    outer = unwrap(points)
    center = center_longitude(outer)
    global_offset = if center, do: round((map_longitude - center) / 360.0) * 360.0, else: 0.0

    holes =
      holes
      |> Enum.map(fn hole ->
        hole = unwrap(hole)
        hole_center = center_longitude(hole)

        offset =
          if center && hole_center,
            do: round((center - hole_center) / 360.0) * 360.0,
            else: 0.0

        to_pixels(hole, global_offset + offset, zoom, origin_x, origin_y)
      end)
      |> Enum.filter(&match?([_, _, _ | _], &1))

    [to_pixels(outer, global_offset, zoom, origin_x, origin_y) | holes]
  end

  # The points of a ring as `{latitude, longitude}`, with no jump of more
  # than 180° of longitude from a point to the next one.
  defp unwrap(points) do
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
  end

  # The middle of the longitudes of a ring, or nil for no point.
  defp center_longitude([]), do: nil

  defp center_longitude(points) do
    {min_lon, max_lon} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    (min_lon + max_lon) / 2.0
  end

  defp to_pixels([], _global_offset, _zoom, _origin_x, _origin_y), do: []

  defp to_pixels(points, global_offset, zoom, origin_x, origin_y) do
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

  # The path of the rings of a polygon with holes: a subpath for each
  # ring. With the rule `evenodd`, each hole is a hole.
  defp path(rings) do
    rings
    |> Enum.reject(&(&1 == []))
    |> Enum.map_join(" ", fn ring -> "M" <> points_attribute(ring) <> "Z" end)
  end
end
