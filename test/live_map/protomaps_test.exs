defmodule LiveMap.MVT.ProtomapsTest do
  # The layers of the Protomaps basemap (version 4) as Shortbread layers:
  # a source with `schema: "protomaps"`.
  use ExUnit.Case, async: true

  alias LiveMap.MVT.Protomaps

  defp feature(layer, type, properties),
    do: %{layer: layer, type: type, properties: properties, geometry: [], extent: 4096}

  defp normalize(layer, type, properties) do
    case Protomaps.normalize(feature(layer, type, properties)) do
      [%{layer: layer, properties: properties}] -> {layer, properties}
      [] -> nil
    end
  end

  test "the land, the water and the rivers" do
    assert normalize("earth", :polygon, %{"kind" => "earth"}) == nil

    assert {"ocean", %{"kind" => "water"}} = normalize("water", :polygon, %{"kind" => "ocean"})

    assert {"water_polygons", %{"kind" => "water", "bridge" => false, "tunnel" => false}} =
             normalize("water", :polygon, %{"kind" => "lake"})

    assert {"water_lines", %{"kind" => "river", "tunnel" => true}} =
             normalize("water", :line, %{"kind" => "river", "tunnel" => true})

    assert {"water_lines", %{"kind" => "water"}} = normalize("water", :line, %{})

    assert {"water_polygons_labels", %{"kind" => "lake", "name" => "Hồ Ba Bể"}} =
             normalize("water", :point, %{"kind" => "lake", "name" => "Hồ Ba Bể"})

    assert {"water_polygons_labels", %{"kind" => "water"}} =
             normalize("water", :point, %{"name" => "Biển Đông"})

    # A label with no name goes.
    assert normalize("water", :point, %{"kind" => "lake"}) == nil
  end

  test "the land cover and the land use" do
    for {kind, shortbread} <- [
          {"grassland", "grass"},
          {"barren", "bare_rock"},
          {"urban_area", "residential"},
          {"forest", "forest"},
          {nil, "default"}
        ] do
      assert {"land", %{"kind" => ^shortbread}} =
               normalize("landcover", :polygon, %{"kind" => kind})
    end

    for {kind, shortbread} <- [
          {"national_park", "park"},
          {"golf_course", "park"},
          {"wood", "forest"},
          {"meadow", "grass"},
          {"grassland", "grass"},
          {"orchard", "farmland"},
          {"cemetery", "cemetery"}
        ] do
      assert {"land", %{"kind" => ^shortbread}} =
               normalize("landuse", :polygon, %{"kind" => kind})
    end

    assert {"land", %{"kind" => "default"}} = normalize("landuse", :polygon, %{})

    assert {"street_polygons", %{"kind" => "runway"}} =
             normalize("landuse", :polygon, %{"kind" => "runway"})

    assert {"pier_polygons", %{"kind" => "pier"}} =
             normalize("landuse", :polygon, %{"kind" => "pier"})

    assert {"buildings", %{"kind" => "building"}} = normalize("buildings", :polygon, %{})
    assert normalize("buildings", :point, %{"kind" => "address"}) == nil
    assert normalize("pois", :point, %{"kind" => "cafe", "name" => "Cà phê"}) == nil
  end

  test "the roads, the railways, the ferries and the runways" do
    assert {"streets", %{"kind" => "motorway", "link" => false}} =
             normalize("roads", :line, %{"kind" => "highway", "kind_detail" => "motorway"})

    assert {"streets", %{"kind" => "trunk", "link" => true}} =
             normalize("roads", :line, %{"kind" => "major_road", "kind_detail" => "trunk_link"})

    assert {"streets", %{"kind" => "primary", "bridge" => true, "tunnel" => false}} =
             normalize("roads", :line, %{
               "kind" => "major_road",
               "kind_detail" => "primary",
               "is_bridge" => true
             })

    assert {"streets", %{"kind" => "tertiary", "tunnel" => true}} =
             normalize("roads", :line, %{"kind" => "major_road", "is_tunnel" => "yes"})

    assert {"streets", %{"kind" => "service"}} =
             normalize("roads", :line, %{"kind" => "minor_road", "kind_detail" => "service"})

    assert {"streets", %{"kind" => "unclassified"}} =
             normalize("roads", :line, %{"kind" => "minor_road", "kind_detail" => "residential"})

    assert {"streets", %{"kind" => "unclassified"}} =
             normalize("roads", :line, %{"kind" => "minor_road"})

    assert {"streets", %{"kind" => "footway"}} =
             normalize("roads", :line, %{"kind" => "path", "kind_detail" => "footway"})

    assert {"streets", %{"kind" => "path"}} = normalize("roads", :line, %{"kind" => "path"})

    assert {"streets", %{"kind" => "taxiway"}} =
             normalize("roads", :line, %{"kind" => "aeroway", "kind_detail" => "taxiway"})

    assert {"streets", %{"kind" => "runway"}} = normalize("roads", :line, %{"kind" => "aeroway"})

    assert {"streets", %{"kind" => "tram"}} =
             normalize("roads", :line, %{"kind" => "rail", "kind_detail" => "tram"})

    assert {"streets", %{"kind" => "rail"}} =
             normalize("roads", :line, %{"kind" => "rail", "kind_detail" => "narrow_gauge"})

    assert {"streets", %{"kind" => "unclassified"}} = normalize("roads", :line, %{})
    assert {"streets", %{"kind" => "track"}} = normalize("roads", :line, %{"kind" => "track"})

    assert {"ferries", %{"kind" => "ferry"}} = normalize("roads", :line, %{"kind" => "ferry"})

    assert {"aerialways", %{"kind" => "gondola"}} =
             normalize("roads", :line, %{"kind" => "aerialway", "kind_detail" => "gondola"})

    assert {"aerialways", %{"kind" => "aerialway"}} =
             normalize("roads", :line, %{"kind" => "aerialway"})

    assert {"pier_lines", %{"kind" => "pier"}} = normalize("roads", :line, %{"kind" => "pier"})
  end

  test "the borders of the countries and of the provinces" do
    assert {"boundaries", %{"kind" => "administrative", "admin_level" => 2}} =
             normalize("boundaries", :line, %{"kind" => "country", "kind_detail" => 2})

    assert {"boundaries", %{"kind" => "administrative", "admin_level" => 4}} =
             normalize("boundaries", :line, %{"kind" => "region", "kind_detail" => 4})

    assert {"boundaries", %{"kind" => "disputed", "admin_level" => 2}} =
             normalize("boundaries", :line, %{
               "kind" => "country",
               "kind_detail" => 2,
               "disputed" => true
             })

    assert {"boundaries", %{"kind" => "disputed", "admin_level" => 2}} =
             normalize("boundaries", :line, %{"kind" => "unrecognized_country"})

    # The borders of the counties are not in Shortbread.
    assert normalize("boundaries", :line, %{"kind" => "county", "kind_detail" => 6}) == nil
  end

  test "the labels of the countries and of the provinces" do
    assert {"boundary_labels",
            %{
              "kind" => "administrative",
              "admin_level" => 2,
              "name" => "Việt Nam",
              "way_area" => 100_000_000_000
            }} =
             normalize("places", :point, %{
               "kind" => "country",
               "name" => "Việt Nam",
               "min_zoom" => 2
             })

    for {min_zoom, area} <- [{3, 25_000_000_000}, {4.5, 0}, {4, 5_000_000_000}, {nil, 0}] do
      assert {"boundary_labels", %{"admin_level" => 4, "way_area" => ^area}} =
               normalize("places", :point, %{
                 "kind" => "region",
                 "name" => "Hà Giang",
                 "min_zoom" => min_zoom
               })
    end
  end

  test "the labels of the places" do
    assert {"place_labels", %{"kind" => "capital", "name" => "Hà Nội", "population" => 8_000_000}} =
             normalize("places", :point, %{
               "kind" => "locality",
               "kind_detail" => "city",
               "capital" => "yes",
               "name" => "Hà Nội",
               "population" => 8_000_000
             })

    assert {"place_labels", %{"kind" => "state_capital", "population" => 0}} =
             normalize("places", :point, %{
               "kind" => "locality",
               "kind_detail" => "town",
               "capital" => "4",
               "name" => "Hà Giang"
             })

    for {detail, kind} <- [
          {"town", "town"},
          {"village", "village"},
          {nil, "locality"},
          {"isolated_dwelling", "locality"}
        ] do
      assert {"place_labels", %{"kind" => ^kind}} =
               normalize("places", :point, %{
                 "kind" => "locality",
                 "kind_detail" => detail,
                 "name" => "Đồng Văn"
               })
    end

    assert {"place_labels", %{"kind" => "suburb"}} =
             normalize("places", :point, %{
               "kind" => "macrohood",
               "kind_detail" => "suburb",
               "name" => "Quận 1"
             })

    assert {"place_labels", %{"kind" => "neighbourhood"}} =
             normalize("places", :point, %{"kind" => "neighbourhood", "name" => "Phố cổ"})

    assert normalize("places", :point, %{"kind" => "locality"}) == nil
  end

  test "the Latin name of a place in another script" do
    assert {"place_labels", %{"name" => "Beijing"}} =
             normalize("places", :point, %{
               "kind" => "locality",
               "name" => "北京市",
               "name:en" => "Beijing",
               "script" => "Han"
             })

    assert {"place_labels", %{"name" => "北京市"}} =
             normalize("places", :point, %{
               "kind" => "locality",
               "name" => "北京市",
               "script" => "Han"
             })

    assert {"place_labels", %{"name" => "Đồng Văn"}} =
             normalize("places", :point, %{
               "kind" => "locality",
               "name" => "Đồng Văn",
               "name:en" => "Dong Van",
               "script" => "Latin"
             })
  end
end
