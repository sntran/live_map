defmodule LiveMap.MVT.OpenMapTilesTest do
  # The layers of OpenMapTiles as Shortbread layers: a source with
  # `schema: "openmaptiles"`.
  use ExUnit.Case, async: true

  alias LiveMap.MVT.OpenMapTiles

  defp feature(layer, type, properties),
    do: %{layer: layer, type: type, properties: properties, geometry: [], extent: 4096}

  defp normalize(layer, type, properties) do
    case OpenMapTiles.normalize(feature(layer, type, properties)) do
      [%{layer: layer, properties: properties}] -> {layer, properties}
      [] -> nil
    end
  end

  test "the water, the rivers and the land" do
    assert {"ocean", %{"kind" => "water"}} = normalize("water", :polygon, %{"class" => "ocean"})

    assert {"water_polygons", %{"tunnel" => true}} =
             normalize("water", :polygon, %{"class" => "lake", "brunnel" => "tunnel"})

    assert {"water_lines", %{"kind" => "river"}} =
             normalize("waterway", :line, %{"class" => "river"})

    assert {"land", %{"kind" => "forest"}} =
             normalize("landcover", :polygon, %{"class" => "wood"})

    assert {"land", %{"kind" => "beach"}} =
             normalize("landcover", :polygon, %{"class" => "sand", "subclass" => "beach"})

    assert {"land", %{"kind" => "grass"}} =
             normalize("landcover", :polygon, %{"class" => "grass"})

    assert {"land", %{"kind" => "default"}} = normalize("landcover", :polygon, %{})

    assert {"land", %{"kind" => "residential"}} =
             normalize("landuse", :polygon, %{"class" => "residential"})

    assert {"land", %{"kind" => "default"}} = normalize("landuse", :polygon, %{})

    assert {"land", %{"kind" => "park"}} =
             normalize("park", :polygon, %{"class" => "national_park"})

    assert {"buildings", _} = normalize("building", :polygon, %{})
  end

  test "the roads, the railways, the ferries and the runways" do
    assert {"streets", %{"kind" => "primary", "bridge" => true, "tunnel" => false}} =
             normalize("transportation", :line, %{"class" => "primary", "brunnel" => "bridge"})

    assert {"streets", %{"kind" => "unclassified"}} =
             normalize("transportation", :line, %{"class" => "minor"})

    assert {"streets", %{"kind" => "subway"}} =
             normalize("transportation", :line, %{"class" => "transit"})

    assert {"streets", %{"kind" => "tram"}} =
             normalize("transportation", :line, %{"class" => "transit", "subclass" => "tram"})

    assert {"streets", %{"kind" => "rail"}} =
             normalize("transportation", :line, %{"class" => "rail"})

    assert {"streets", %{"kind" => "footway"}} =
             normalize("transportation", :line, %{"class" => "path", "subclass" => "footway"})

    assert {"ferries", _} = normalize("transportation", :line, %{"class" => "ferry"})

    assert {"aerialways", %{"kind" => "gondola"}} =
             normalize("transportation", :line, %{"class" => "gondola"})

    assert {"pier_polygons", _} = normalize("transportation", :polygon, %{"class" => "pier"})

    assert {"street_polygons", %{"kind" => "runway"}} =
             normalize("aeroway", :polygon, %{"class" => "runway"})

    assert normalize("aeroway", :polygon, %{"class" => "aerodrome"}) == nil
  end

  test "the borders of the countries and the provinces" do
    assert {"boundaries", %{"admin_level" => 2, "kind" => "administrative"}} =
             normalize("boundary", :line, %{"admin_level" => 2})

    assert {"boundaries", %{"kind" => "disputed"}} =
             normalize("boundary", :line, %{"admin_level" => 4, "disputed" => 1})

    assert normalize("boundary", :line, %{"admin_level" => 2, "maritime" => 1}) == nil
    assert normalize("boundary", :line, %{"admin_level" => 6}) == nil
  end

  test "the names of the places, in Latin, with their priority" do
    assert {"place_labels", %{"kind" => "capital", "name" => "Hanoi", "population" => 1_000_000}} =
             normalize("place", :point, %{
               "class" => "city",
               "capital" => 2,
               "rank" => 2,
               "name" => "Hà Nội",
               "name:latin" => "Hanoi"
             })

    assert {"place_labels", %{"kind" => "state_capital", "population" => 250_000}} =
             normalize("place", :point, %{"class" => "city", "capital" => 4, "name" => "Hà Giang"})

    assert {"place_labels", %{"kind" => "town", "population" => 50_000}} =
             normalize("place", :point, %{"class" => "town", "name" => "Đồng Văn"})

    assert {"place_labels", %{"kind" => "locality", "population" => 0}} =
             normalize("place", :point, %{"class" => "isolated_dwelling", "name" => "Nhà"})

    assert {"boundary_labels", %{"admin_level" => 2, "way_area" => 100_000_000_000}} =
             normalize("place", :point, %{"class" => "country", "rank" => 1, "name" => "Việt Nam"})

    assert {"boundary_labels", %{"admin_level" => 4, "way_area" => 25_000_000_000}} =
             normalize("place", :point, %{"class" => "state", "rank" => 3, "name" => "Hà Giang"})

    assert {"boundary_labels", %{"way_area" => 5_000_000_000}} =
             normalize("place", :point, %{"class" => "province", "name" => "Cao Bằng"})

    assert {"water_polygons_labels", %{"kind" => "lake", "name" => "Hồ Tây"}} =
             normalize("water_name", :point, %{"class" => "lake", "name" => "Hồ Tây"})

    assert {"water_polygons_labels", %{"kind" => "water"}} =
             normalize("water_name", :point, %{"name" => "Biển Đông"})

    # A label with no name, and the layers that LiveMap does not draw.
    assert normalize("place", :point, %{"class" => "village"}) == nil
    assert normalize("poi", :point, %{"name" => "Café"}) == nil
    assert normalize("housenumber", :point, %{"housenumber" => "12"}) == nil
    assert normalize("transportation_name", :line, %{"name" => "QL4C"}) == nil
  end

  test "a tile of OpenMapTiles decodes into an SVG with the classes of Shortbread" do
    # A tile with one layer "water" and one square polygon, in the format
    # of Mapbox Vector Tile 2.
    square = [9, 0, 0, 26, 8192, 0, 0, 8192, 8191, 0, 15]

    feature =
      field(2, varints([0, 0])) <>
        <<3::size(5), 0::size(3)>> <> <<3>> <> field(4, varints(square))

    layer =
      field(1, "water") <>
        field(2, feature) <>
        field(3, "class") <>
        field(4, field(1, "lake")) <>
        <<15::size(5), 0::size(3), 2>> <> <<5::size(5), 0::size(3)>> <> varint(4096)

    tile = field(3, layer)

    assert {:ok, svg} = LiveMap.MVT.decode(tile, schema: "openmaptiles", zoom: 12)
    svg = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    assert svg =~ "live-map-shortbread-layer-water-polygons"
    assert svg =~ "live-map-shortbread-role-water"
  end

  # The protocol buffers of a vector tile.
  defp field(number, bytes),
    do: <<number::size(5), 2::size(3)>> <> varint(byte_size(bytes)) <> bytes

  defp varints(values), do: Enum.map_join(values, &varint/1)

  defp varint(value) when value < 128, do: <<value>>

  defp varint(value),
    do: <<Bitwise.bor(Bitwise.band(value, 127), 128)>> <> varint(Bitwise.bsr(value, 7))
end
