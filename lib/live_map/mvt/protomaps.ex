defmodule LiveMap.MVT.Protomaps do
  @moduledoc false
  # The features of a tile of the Protomaps basemap (version 4, as the
  # builds of Protomaps) as features of the Shortbread schema, so the CSS
  # and the styles of LiveMap draw them, as LiveMap.MVT.OpenMapTiles does
  # for OpenMapTiles. A feature that LiveMap does not draw (a point of
  # interest, a house number, the land under the map) goes.
  #
  # The layers: https://docs.protomaps.com/basemaps/layers

  # The parks of Shortbread.
  @parks ~w(park national_park nature_reserve protected_area garden dog_park recreation_ground
            golf_course playground)

  @doc """
  The Shortbread features of a Protomaps feature: none, or one.
  """
  @spec normalize(map()) :: [map()]
  def normalize(%{layer: layer, properties: properties} = feature) do
    case shortbread(layer, feature.type, properties) do
      nil -> []
      # A label with no name.
      {_layer, %{"name" => nil}} -> []
      {new_layer, new_properties} -> [%{feature | layer: new_layer, properties: new_properties}]
    end
  end

  # The land is the background of the map.
  defp shortbread("earth", _type, _properties), do: nil

  defp shortbread("water", :polygon, %{"kind" => "ocean"} = properties),
    do: {"ocean", water("water", properties)}

  defp shortbread("water", :polygon, properties),
    do: {"water_polygons", water("water", properties)}

  defp shortbread("water", :line, properties),
    do: {"water_lines", water(properties["kind"], properties)}

  defp shortbread("water", :point, properties),
    do:
      {"water_polygons_labels",
       %{"kind" => properties["kind"] || "water", "name" => name(properties)}}

  defp shortbread("landcover", :polygon, %{"kind" => kind}),
    do: {"land", %{"kind" => landcover(kind)}}

  defp shortbread("landuse", :polygon, %{"kind" => kind}) when kind in ["runway", "taxiway"],
    do: {"street_polygons", %{"kind" => kind}}

  defp shortbread("landuse", :polygon, %{"kind" => "pier"}),
    do: {"pier_polygons", %{"kind" => "pier"}}

  defp shortbread("landuse", :polygon, properties),
    do: {"land", %{"kind" => landuse(properties["kind"])}}

  defp shortbread("roads", :line, %{"kind" => "ferry"}), do: {"ferries", %{"kind" => "ferry"}}

  defp shortbread("roads", :line, %{"kind" => "aerialway"} = properties),
    do: {"aerialways", %{"kind" => properties["kind_detail"] || "aerialway"}}

  defp shortbread("roads", :line, %{"kind" => "pier"}), do: {"pier_lines", %{"kind" => "pier"}}

  defp shortbread("roads", :line, properties) do
    {kind, link?} = street(properties["kind"], properties["kind_detail"])

    {"streets",
     %{
       "kind" => kind,
       "link" => link?,
       "bridge" => truthy?(properties["is_bridge"]),
       "tunnel" => truthy?(properties["is_tunnel"])
     }}
  end

  defp shortbread("buildings", :polygon, _properties), do: {"buildings", %{"kind" => "building"}}

  defp shortbread("boundaries", :line, %{"kind" => "unrecognized_country"}),
    do: {"boundaries", %{"kind" => "disputed", "admin_level" => 2}}

  # The borders of the countries and of the provinces only, as in
  # Shortbread: the admin level is the kind_detail.
  defp shortbread("boundaries", :line, %{"kind_detail" => level} = properties)
       when level in [2, 4],
       do:
         {"boundaries",
          %{
            "kind" => if(truthy?(properties["disputed"]), do: "disputed", else: "administrative"),
            "admin_level" => level
          }}

  defp shortbread("places", :point, %{"kind" => kind} = properties)
       when kind in ["country", "region"] do
    {"boundary_labels",
     %{
       "kind" => "administrative",
       "admin_level" => if(kind == "country", do: 2, else: 4),
       "name" => name(properties),
       "way_area" => area(properties["min_zoom"])
     }}
  end

  defp shortbread("places", :point, %{"kind" => kind} = properties)
       when kind in ["locality", "macrohood", "neighbourhood"] do
    {"place_labels",
     %{
       "kind" => place(kind, properties["kind_detail"], properties["capital"]),
       "name" => name(properties),
       "population" => population(properties["population"])
     }}
  end

  defp shortbread(_layer, _type, _properties), do: nil

  # The kind of a water feature, and its bridge or tunnel.
  defp water(kind, properties) do
    %{
      "kind" => kind || "water",
      "bridge" => truthy?(properties["bridge"]),
      "tunnel" => truthy?(properties["tunnel"])
    }
  end

  defp landcover("grassland"), do: "grass"
  defp landcover("barren"), do: "bare_rock"
  defp landcover("urban_area"), do: "residential"
  defp landcover(kind), do: kind || "default"

  defp landuse(kind) when kind in @parks, do: "park"
  defp landuse("wood"), do: "forest"
  defp landuse(kind) when kind in ["grassland", "meadow"], do: "grass"
  defp landuse("orchard"), do: "farmland"
  defp landuse(kind), do: kind || "default"

  # The kind of a road of Shortbread, and if it is a link. The small roads
  # are "unclassified" in Shortbread, as with OpenMapTiles; a railway and a
  # path keep the kind of their detail.
  defp street("highway", _detail), do: {"motorway", false}

  defp street(kind, detail) when is_binary(detail) and kind in ["major_road", "minor_road"] do
    case String.split(detail, "_link") do
      [road, ""] -> {road, true}
      _other -> {minor(kind, detail), false}
    end
  end

  defp street("minor_road", _detail), do: {"unclassified", false}
  defp street("major_road", _detail), do: {"tertiary", false}
  defp street("path", detail), do: {detail || "path", false}
  defp street("aeroway", detail), do: {detail || "runway", false}

  defp street("rail", detail)
       when detail in ["subway", "tram", "light_rail", "funicular", "monorail"],
       do: {detail, false}

  defp street("rail", _detail), do: {"rail", false}
  defp street(kind, _detail), do: {kind || "unclassified", false}

  defp minor("minor_road", "service"), do: "service"
  defp minor("minor_road", _detail), do: "unclassified"
  defp minor("major_road", detail), do: detail

  defp place(_kind, _detail, capital) when capital in ["yes", "2"], do: "capital"
  defp place(_kind, _detail, "4"), do: "state_capital"

  defp place("locality", detail, _capital)
       when detail in [nil, "isolated_dwelling", "farm", "allotments"],
       do: "locality"

  defp place(_kind, nil, _capital), do: "neighbourhood"
  defp place(_kind, detail, _capital), do: detail

  # The Latin name first, as the maps of MapLibre: a name in another
  # script has `script`, and its English name in `name:en`.
  defp name(%{"script" => script} = properties) when is_binary(script) and script != "Latin",
    do: properties["name:en"] || properties["name"]

  defp name(properties), do: properties["name"]

  defp population(population) when is_integer(population), do: population
  defp population(_population), do: 0

  # The first zoom level of a label of a country or a province gives its
  # priority, as the area of its land in Shortbread.
  defp area(min_zoom) when is_number(min_zoom) and min_zoom <= 2, do: 100_000_000_000
  defp area(min_zoom) when is_number(min_zoom) and min_zoom <= 3, do: 25_000_000_000
  defp area(min_zoom) when is_number(min_zoom) and min_zoom <= 4, do: 5_000_000_000
  defp area(_min_zoom), do: 0

  defp truthy?(value), do: value in [true, 1, "yes", "true"]
end
