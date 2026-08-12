defmodule LiveMap.Style do
  @moduledoc """
  Translates Google Maps style JSON and LiveMap base-style presets into SVG CSS
  rules for vector tiles.
  """

  @detailed_svg_css """
  /* LiveMap detailed SVG preset */
  .live-map-tile-svg { background: var(--live-map-detailed-background, #f8f5ef); }

  .live-map-shortbread-role-land.live-map-shortbread-shape-polygon {
    fill: var(--live-map-detailed-land-fill, #f8f5ef);
  }
  .live-map-shortbread-role-land.live-map-shortbread-kind-forest {
    fill: var(--live-map-detailed-forest-fill, #dce8d2);
    fill-opacity: 1;
  }
  .live-map-shortbread-role-land.live-map-shortbread-kind-park,
  .live-map-shortbread-role-land.live-map-shortbread-kind-grass {
    fill: var(--live-map-detailed-park-fill, #e2ecd8);
  }
  .live-map-shortbread-role-land.live-map-shortbread-kind-farmland {
    fill: var(--live-map-detailed-farmland-fill, #eee9d8);
  }
  .live-map-shortbread-role-land.live-map-shortbread-kind-sand,
  .live-map-shortbread-role-land.live-map-shortbread-kind-beach {
    fill: var(--live-map-detailed-sand-fill, #f5edcf);
  }
  .live-map-shortbread-role-water.live-map-shortbread-shape-polygon {
    fill: var(--live-map-detailed-water-fill, #aee0f4);
  }
  .live-map-shortbread-role-water.live-map-shortbread-shape-line {
    stroke: var(--live-map-detailed-water-line-stroke, #94cfe7);
  }
  .live-map-shortbread-role-site.live-map-shortbread-shape-polygon {
    fill: var(--live-map-detailed-site-fill, #e9e5dd);
    fill-opacity: 0.55;
  }
  .live-map-shortbread-role-building.live-map-shortbread-shape-polygon {
    fill: var(--live-map-detailed-building-fill, #e8e3dd);
    stroke: var(--live-map-detailed-building-stroke, #d8d2cc);
  }

  .live-map-shortbread-role-street.live-map-shortbread-shape-line {
    stroke: var(--live-map-detailed-road-stroke, #ffffff);
    stroke-width: var(--live-map-detailed-road-width, 0.0055);
  }
  .live-map-shortbread-role-street.live-map-shortbread-kind-motorway {
    stroke: var(--live-map-detailed-motorway-stroke, #e9b873);
    stroke-width: var(--live-map-detailed-motorway-width, 0.014);
  }
  .live-map-shortbread-role-street.live-map-shortbread-kind-trunk {
    stroke: var(--live-map-detailed-trunk-stroke, #efd094);
    stroke-width: var(--live-map-detailed-trunk-width, 0.012);
  }
  .live-map-shortbread-role-street.live-map-shortbread-kind-primary {
    stroke: var(--live-map-detailed-primary-stroke, #f3dda9);
    stroke-width: var(--live-map-detailed-primary-width, 0.01);
  }
  .live-map-shortbread-role-street.live-map-shortbread-kind-secondary {
    stroke: var(--live-map-detailed-secondary-stroke, #f7e8c6);
    stroke-width: var(--live-map-detailed-secondary-width, 0.008);
  }
  .live-map-shortbread-role-street.live-map-shortbread-kind-tertiary {
    stroke-width: var(--live-map-detailed-tertiary-width, 0.0065);
  }
  .live-map-shortbread-role-street.live-map-shortbread-kind-rail {
    stroke: var(--live-map-detailed-rail-stroke, #aaa6a1);
    stroke-dasharray: 0.006 0.004;
  }

  .live-map-shortbread-role-boundary.live-map-shortbread-admin-level-2.live-map-shortbread-shape-line {
    stroke: var(--live-map-detailed-country-boundary-stroke, #77736f);
    stroke-width: var(--live-map-detailed-country-boundary-width, 0.003);
  }
  .live-map-shortbread-role-boundary.live-map-shortbread-admin-level-4.live-map-shortbread-shape-line {
    stroke: var(--live-map-detailed-state-boundary-stroke, #9d9994);
    stroke-width: var(--live-map-detailed-state-boundary-width, 0.002);
    stroke-dasharray: 0.004 0.003;
  }
  .live-map-shortbread-role-boundary.live-map-shortbread-admin-level-6.live-map-shortbread-shape-line,
  .live-map-shortbread-role-boundary.live-map-shortbread-admin-level-8.live-map-shortbread-shape-line {
    stroke: var(--live-map-detailed-local-boundary-stroke, #c2beb8);
    stroke-width: var(--live-map-detailed-local-boundary-width, 0.0015);
    stroke-dasharray: 0.003 0.003;
  }

  .live-map-shortbread-layer-boundary-labels.live-map-shortbread-admin-level-2.live-map-shortbread-shape-text {
    font-size: var(--live-map-detailed-country-label-size, 0.052px);
    font-weight: 650;
    letter-spacing: 0.004px;
  }
  .live-map-shortbread-layer-boundary-labels.live-map-shortbread-admin-level-4.live-map-shortbread-shape-text {
    fill: var(--live-map-detailed-state-label-fill, #74716e);
    font-size: var(--live-map-detailed-state-label-size, 0.033px);
    font-weight: 550;
    letter-spacing: 0.003px;
  }
  .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-capital.live-map-shortbread-shape-text,
  .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-state-capital.live-map-shortbread-shape-text {
    font-size: var(--live-map-detailed-capital-label-size, 0.043px);
    font-weight: 650;
  }

  .live-map-tile-svg[data-live-map-label-density="overview"]
    :is(
      .live-map-shortbread-layer-boundary-labels.live-map-shortbread-admin-level-2,
      .live-map-shortbread-layer-boundary-labels.live-map-shortbread-admin-level-4,
      .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-capital,
      .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-state-capital
    ).live-map-shortbread-shape-text {
    display: none;
  }
  .live-map-tile-svg[data-live-map-label-density="overview"]
    :is(
      .live-map-shortbread-layer-boundary-labels.live-map-shortbread-admin-level-2,
      .live-map-shortbread-layer-boundary-labels.live-map-shortbread-admin-level-4,
      .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-capital
    ).live-map-shortbread-label-priority-1.live-map-shortbread-shape-text {
    display: inline;
  }

  .live-map-tile-svg[data-live-map-label-density="regional"]
    :is(
      .live-map-shortbread-layer-boundary-labels.live-map-shortbread-admin-level-2,
      .live-map-shortbread-layer-boundary-labels.live-map-shortbread-admin-level-4,
      .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-capital,
      .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-state-capital
    ).live-map-shortbread-shape-text {
    display: none;
  }
  .live-map-tile-svg[data-live-map-label-density="regional"]
    :is(
      .live-map-shortbread-layer-boundary-labels.live-map-shortbread-admin-level-2,
      .live-map-shortbread-layer-boundary-labels.live-map-shortbread-admin-level-4,
      .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-capital
    ):is(
      .live-map-shortbread-label-priority-1,
      .live-map-shortbread-label-priority-2
    ).live-map-shortbread-shape-text,
  .live-map-tile-svg[data-live-map-label-density="regional"]
    .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-state-capital.live-map-shortbread-label-priority-1.live-map-shortbread-shape-text {
    display: inline;
  }
  .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-city.live-map-shortbread-label-priority-1.live-map-shortbread-shape-text,
  .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-city.live-map-shortbread-label-priority-2.live-map-shortbread-shape-text {
    display: inline;
    font-size: var(--live-map-detailed-major-city-label-size, 0.041px);
    font-weight: 600;
  }
  .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-town.live-map-shortbread-label-priority-1.live-map-shortbread-shape-text,
  .live-map-shortbread-layer-place-labels.live-map-shortbread-kind-town.live-map-shortbread-label-priority-2.live-map-shortbread-shape-text {
    display: inline;
    font-size: var(--live-map-detailed-major-town-label-size, 0.037px);
    font-weight: 550;
  }
  """

  @physical_svg_css """
  /* LiveMap physical SVG overlay preset */
  .live-map-tile-svg:is(
    .live-map-zoom-0,
    .live-map-zoom-1,
    .live-map-zoom-2,
    .live-map-zoom-3,
    .live-map-zoom-4,
    .live-map-zoom-5,
    .live-map-zoom-6,
    .live-map-zoom-7,
    .live-map-zoom-8,
    .live-map-zoom-9
  ) {
    background: transparent;
  }

  .live-map-tile-svg:is(
    .live-map-zoom-0,
    .live-map-zoom-1,
    .live-map-zoom-2,
    .live-map-zoom-3,
    .live-map-zoom-4,
    .live-map-zoom-5,
    .live-map-zoom-6,
    .live-map-zoom-7,
    .live-map-zoom-8,
    .live-map-zoom-9
  ) :is(
    .live-map-shortbread-role-land,
    .live-map-shortbread-role-water
  ).live-map-shortbread-shape-polygon {
    fill-opacity: 0.12 !important;
  }

  .live-map-tile-svg:is(
    .live-map-zoom-0,
    .live-map-zoom-1,
    .live-map-zoom-2,
    .live-map-zoom-3,
    .live-map-zoom-4,
    .live-map-zoom-5,
    .live-map-zoom-6,
    .live-map-zoom-7,
    .live-map-zoom-8,
    .live-map-zoom-9
  ) :is(
    .live-map-shortbread-role-site,
    .live-map-shortbread-role-building
  ).live-map-shortbread-shape-polygon {
    fill-opacity: 0.25 !important;
  }
  """

  @base_styles ~w(colorful detailed physical)

  @doc """
  Converts a list of Google Maps style JSON objects into a CSS string.
  """
  def to_css(styles) when is_list(styles) do
    styles
    |> Enum.flat_map(&process_style/1)
    |> Enum.join("\n")
  end

  def to_css(_), do: ""

  @doc """
  Builds the CSS for a LiveMap vector base-style preset, followed by any Google
  Maps style rules so application-specific overrides retain precedence.
  """
  def to_css(styles, base_style) when base_style in @base_styles do
    [base_style_css(base_style), to_css(styles)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  def to_css(_styles, base_style) do
    raise ArgumentError,
          "base-style must be one of #{Enum.join(@base_styles, ", ")}; got: #{inspect(base_style)}"
  end

  defp base_style_css("colorful"), do: ""
  defp base_style_css("detailed"), do: String.trim(@detailed_svg_css)

  defp base_style_css("physical") do
    Enum.join([String.trim(@detailed_svg_css), String.trim(@physical_svg_css)], "\n")
  end

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
    stylers
    |> Enum.map(&compile_styler(&1, element_type))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp compile_styler(%{"visibility" => "off"}, "labels.text.stroke"),
    do: "stroke: none !important;"

  defp compile_styler(%{"visibility" => "off"}, _), do: "display: none !important;"
  defp compile_styler(%{"visibility" => "on"}, _), do: "display: block !important;"

  defp compile_styler(%{"visibility" => "simplified"}, _),
    do: "display: block !important;"

  defp compile_styler(%{"color" => color}, element_type) do
    case element_type do
      "geometry.stroke" ->
        "stroke: #{color} !important;"

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

  defp compile_styler(%{"weight" => weight}, _) when is_number(weight) do
    "stroke-width: #{weight / 100}px !important;"
  end

  defp compile_styler(%{"weight" => weight}, _) when is_binary(weight) do
    case Float.parse(weight) do
      {w, _} -> "stroke-width: #{w / 100}px !important;"
      :error -> nil
    end
  end

  defp compile_styler(_, _), do: nil
end
