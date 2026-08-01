defmodule LiveMap.Marker do
  @moduledoc false

  alias LiveMap.Tile

  def project(marker_slot, map_id, zoom, min_x, min_y, index) do
    latitude = parse_float(marker_slot.latitude)
    longitude = parse_float(marker_slot.longitude)
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

  def project_shape(type, shape_slot, map_id, zoom, min_x, min_y, index) when type in [:polygon, :polyline] do
    id = normalize_id(Map.get(shape_slot, :id))
    label = Map.get(shape_slot, :label)
    points = project_points(Map.fetch!(shape_slot, :points), zoom, min_x, min_y)

    %{
      type: type,
      id: id,
      dom_id: shape_dom_id(type, map_id, id, index),
      label: label,
      points: points,
      points_attribute: points_attribute(points)
    }
  end

  defp dom_id(map_id, nil, index), do: "#{map_id}-marker-#{index}"
  defp dom_id(map_id, id, _index), do: "#{map_id}-marker-#{id}"

  defp shape_dom_id(type, map_id, nil, index), do: "#{map_id}-#{type}-#{index}"
  defp shape_dom_id(type, map_id, id, _index), do: "#{map_id}-#{type}-#{id}"

  defp normalize_id(nil), do: nil
  defp normalize_id(id), do: to_string(id)

  defp project_points(points, zoom, min_x, min_y) do
    Enum.map(points, fn point ->
      latitude = parse_float(Map.fetch!(point, :latitude))
      longitude = parse_float(Map.fetch!(point, :longitude))
      x = Float.round(Tile.x(longitude, zoom) * 256 - min_x, 2)
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
