defmodule LiveMap.Marker do
  @moduledoc false

  alias LiveMap.Tile

  @pixel_scale 1 / 256

  def project(marker_slot, map_id, zoom, index) do
    latitude = parse_float(marker_slot.latitude)
    longitude = parse_float(marker_slot.longitude)
    id = normalize_id(Map.get(marker_slot, :id))
    label = marker_slot.label
    x = Tile.x(longitude, zoom)
    y = Tile.y(latitude, zoom)

    %{
      id: id,
      dom_id: dom_id(map_id, id, index),
      label: label,
      latitude: latitude,
      longitude: longitude,
      x: x,
      y: y,
      scale: @pixel_scale,
      slot: marker_slot,
      has_body: has_body?(marker_slot)
    }
  end

  defp dom_id(map_id, nil, index), do: "#{map_id}-marker-#{index}"
  defp dom_id(map_id, id, _index), do: "#{map_id}-marker-#{id}"

  defp normalize_id(nil), do: nil
  defp normalize_id(id), do: to_string(id)

  defp has_body?(marker_slot) do
    Map.get(marker_slot, :inner_block) not in [nil, []]
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
