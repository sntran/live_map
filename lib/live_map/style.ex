defmodule LiveMap.Style do
  @moduledoc """
  Translates Google Maps style JSON into SVG CSS rules for LiveMap tiles.
  """

  @doc """
  Converts a list of Google Maps style JSON objects into a CSS string.
  """
  def to_css(styles) when is_list(styles) do
    styles
    |> Enum.flat_map(&process_style/1)
    |> Enum.join("\n")
  end

  def to_css(_), do: ""

  defp process_style(style) do
    feature_type = Map.get(style, "featureType", "all")
    element_type = Map.get(style, "elementType", "all")
    stylers = Map.get(style, "stylers", [])

    base_selectors = feature_selectors(feature_type, element_type)
    generate_rules(base_selectors, element_type, stylers)
  end

  defp generate_rules(base_selectors, element_type, stylers) do
    selectors = String.split(base_selectors, ",") |> Enum.map(&String.trim/1)

    cond do
      String.starts_with?(element_type, "labels") ->
        sels = Enum.map(selectors, &"#{&1}.live-map-shortbread-shape-text")
        styles = compile_stylers(stylers, element_type)
        if styles != "", do: ["#{Enum.join(sels, ", ")} { #{styles} }"], else: []

      element_type == "geometry.fill" ->
        sels =
          Enum.map(
            selectors,
            &"#{&1}:not(.live-map-shortbread-shape-text):not(.live-map-shortbread-shape-line)"
          )

        styles = compile_stylers(stylers, element_type)
        if styles != "", do: ["#{Enum.join(sels, ", ")} { #{styles} }"], else: []

      element_type == "geometry.stroke" ->
        sels = Enum.map(selectors, &"#{&1}:not(.live-map-shortbread-shape-text)")
        styles = compile_stylers(stylers, element_type)
        if styles != "", do: ["#{Enum.join(sels, ", ")} { #{styles} }"], else: []

      # "geometry" or "all"
      true ->
        fill_sels =
          Enum.map(
            selectors,
            &"#{&1}:not(.live-map-shortbread-shape-text):not(.live-map-shortbread-shape-line)"
          )

        stroke_sels = Enum.map(selectors, &"#{&1}.live-map-shortbread-shape-line")
        label_sels = Enum.map(selectors, &"#{&1}.live-map-shortbread-shape-text")

        fill_styles = compile_stylers(stylers, "geometry.fill")
        stroke_styles = compile_stylers(stylers, "geometry.stroke")
        label_styles = if element_type == "all", do: compile_stylers(stylers, "labels"), else: ""

        rules = []

        rules =
          if fill_styles != "",
            do: ["#{Enum.join(fill_sels, ", ")} { #{fill_styles} }" | rules],
            else: rules

        rules =
          if stroke_styles != "",
            do: ["#{Enum.join(stroke_sels, ", ")} { #{stroke_styles} }" | rules],
            else: rules

        rules =
          if label_styles != "",
            do: ["#{Enum.join(label_sels, ", ")} { #{label_styles} }" | rules],
            else: rules

        rules
    end
  end

  defp feature_selectors("all", _element_type), do: ".live-map-shortbread-feature"

  defp feature_selectors("administrative", _element_type),
    do: ".live-map-shortbread-role-boundary"

  defp feature_selectors("administrative.country", _element_type),
    do: ".live-map-shortbread-role-boundary.live-map-shortbread-admin-level-2"

  defp feature_selectors("administrative.land_parcel", _element_type),
    do: ".live-map-shortbread-role-boundary.live-map-shortbread-kind-aboriginal_lands"

  defp feature_selectors("administrative.locality", _element_type),
    do:
      ".live-map-shortbread-layer-place-labels.live-map-shortbread-kind-capital, .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-state-capital, .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-city, .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-town"

  defp feature_selectors("administrative.neighborhood", _element_type),
    do:
      ".live-map-shortbread-layer-place-labels.live-map-shortbread-kind-neighborhood, .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-neighbourhood, .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-suburb, .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-quarter"

  defp feature_selectors("administrative.province", _element_type),
    do: ".live-map-shortbread-role-boundary.live-map-shortbread-admin-level-4"

  defp feature_selectors("landscape", _element_type),
    do: ".live-map-shortbread-role-land, .live-map-tile-svg"

  defp feature_selectors("landscape.man_made", _element_type),
    do: ".live-map-shortbread-role-site"

  defp feature_selectors("landscape.natural", _element_type),
    do:
      ".live-map-shortbread-role-land.live-map-shortbread-kind-forest, .live-map-shortbread-role-land.live-map-shortbread-kind-park, .live-map-shortbread-role-land.live-map-shortbread-kind-grass"

  defp feature_selectors("landscape.natural.landcover", _element_type),
    do:
      ".live-map-shortbread-role-land.live-map-shortbread-kind-forest, .live-map-shortbread-role-land.live-map-shortbread-kind-park, .live-map-shortbread-role-land.live-map-shortbread-kind-grass"

  defp feature_selectors("landscape.natural.terrain", _element_type),
    do:
      ".live-map-shortbread-role-land.live-map-shortbread-kind-sand, .live-map-shortbread-role-land.live-map-shortbread-kind-beach, .live-map-shortbread-role-land.live-map-shortbread-kind-farmland"

  defp feature_selectors("poi", _element_type),
    do: ".live-map-shortbread-layer-pois, .live-map-shortbread-layer-public-transport"

  defp feature_selectors("poi.attraction", _element_type),
    do: ".live-map-shortbread-layer-pois.live-map-shortbread-kind-attraction"

  defp feature_selectors("poi.business", _element_type),
    do:
      ".live-map-shortbread-layer-pois.live-map-shortbread-kind-business, .live-map-shortbread-layer-pois.live-map-shortbread-kind-shop"

  defp feature_selectors("poi.government", _element_type),
    do: ".live-map-shortbread-layer-pois.live-map-shortbread-kind-government"

  defp feature_selectors("poi.medical", _element_type),
    do:
      ".live-map-shortbread-layer-pois.live-map-shortbread-kind-medical, .live-map-shortbread-layer-pois.live-map-shortbread-kind-hospital, .live-map-shortbread-layer-pois.live-map-shortbread-kind-clinic, .live-map-shortbread-layer-pois.live-map-shortbread-kind-doctors, .live-map-shortbread-layer-pois.live-map-shortbread-kind-pharmacy"

  defp feature_selectors("poi.park", _element_type),
    do: ".live-map-shortbread-role-land.live-map-shortbread-kind-park"

  defp feature_selectors("poi.place_of_worship", _element_type),
    do: ".live-map-shortbread-layer-pois.live-map-shortbread-kind-place-of-worship"

  defp feature_selectors("poi.school", _element_type),
    do: ".live-map-shortbread-layer-pois.live-map-shortbread-kind-school"

  defp feature_selectors("poi.sports_complex", _element_type),
    do: ".live-map-shortbread-layer-pois.live-map-shortbread-kind-sports-centre"

  defp feature_selectors("road", _element_type),
    do: ".live-map-shortbread-role-street, .live-map-shortbread-role-bridge"

  defp feature_selectors("road.arterial", _element_type),
    do:
      ".live-map-shortbread-role-street.live-map-shortbread-kind-primary, .live-map-shortbread-role-street.live-map-shortbread-kind-secondary, .live-map-shortbread-role-street.live-map-shortbread-kind-tertiary"

  defp feature_selectors("road.highway", _element_type),
    do:
      ".live-map-shortbread-role-street.live-map-shortbread-kind-motorway, .live-map-shortbread-role-street.live-map-shortbread-kind-trunk"

  defp feature_selectors("road.highway.controlled_access", _element_type),
    do: ".live-map-shortbread-role-street.live-map-shortbread-kind-motorway"

  defp feature_selectors("road.local", _element_type),
    do:
      ".live-map-shortbread-role-street.live-map-shortbread-kind-street, .live-map-shortbread-role-street.live-map-shortbread-kind-pedestrian"

  defp feature_selectors("transit", _element_type),
    do:
      ".live-map-shortbread-role-street.live-map-shortbread-kind-rail, .live-map-shortbread-role-street.live-map-shortbread-kind-tram, .live-map-shortbread-role-street.live-map-shortbread-kind-subway"

  defp feature_selectors("transit.line", _element_type),
    do:
      ".live-map-shortbread-role-street.live-map-shortbread-kind-rail, .live-map-shortbread-role-street.live-map-shortbread-kind-tram, .live-map-shortbread-role-street.live-map-shortbread-kind-subway"

  defp feature_selectors("transit.station", _element_type),
    do: ".live-map-shortbread-layer-public-transport"

  defp feature_selectors("water", _element_type), do: ".live-map-shortbread-role-water"
  defp feature_selectors(_, _element_type), do: ".live-map-shortbread-feature"

  defp compile_stylers(stylers, element_type) do
    has_weight? = Enum.any?(stylers, &Map.has_key?(&1, "weight"))

    stylers
    |> Enum.map(&compile_styler(&1, element_type, has_weight?))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp compile_styler(%{"visibility" => "off"}, _, _), do: "display: none !important;"
  defp compile_styler(%{"visibility" => "on"}, _, _), do: "display: block !important;"

  defp compile_styler(%{"visibility" => "simplified"}, _, _),
    do: "display: block !important;"

  defp compile_styler(%{"color" => color}, element_type, has_weight?) do
    case element_type do
      "geometry.stroke" ->
        if has_weight? do
          "stroke: #{color} !important;"
        else
          "stroke: #{color} !important; stroke-width: 0.004px !important;"
        end

      "geometry.fill" ->
        "fill: #{color} !important;"

      # Shouldn't happen
      "geometry" ->
        "fill: #{color} !important; stroke: #{color} !important;"

      "labels.text.stroke" ->
        "stroke: #{color} !important;"

      "labels.text.fill" ->
        "fill: #{color} !important;"

      "labels" ->
        "fill: #{color} !important; stroke: #{color} !important;"

      _ ->
        "fill: #{color} !important; stroke: #{color} !important;"
    end
  end

  defp compile_styler(%{"weight" => weight}, _, _) when is_number(weight) do
    "stroke-width: #{weight / 100}px !important;"
  end

  defp compile_styler(%{"weight" => weight}, _, _) when is_binary(weight) do
    case Float.parse(weight) do
      {w, _} -> "stroke-width: #{w / 100}px !important;"
      :error -> nil
    end
  end

  defp compile_styler(_, _, _), do: nil
end
