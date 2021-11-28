defmodule LiveMapTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  doctest LiveMap

  import Phoenix.LiveViewTest

  describe "container" do

    test "renders component as an SVG" do
      assert component() =~ "</svg>"
    end

    test "contains a <style> descendant" do
      assert component() =~ "</style>"
    end

    test "supports setting width" do
      assert component(width: 300) =~ "width=\"300\""
    end

    test "supports setting height" do
      assert component(height: 150) =~ "height=\"150\""
    end

    test "supports setting title as <title>" do
      assert component(title: "Awesome Live Map") =~ "<title>Awesome Live Map</title>"
    end

  end

  describe "tiles" do
    test "should throw at negative zoom level" do
      assert_raise FunctionClauseError, fn ->
        component(zoom: -1)
      end
    end

    test "should have 1 tile covering the whole wold at zoom 0" do
      rendered = component(zoom: 0)
      {:ok, document} = Floki.parse_document(rendered)
      assert [tile] = Floki.find(document, "image")
      assert Floki.attribute(tile, "x") === ["0"]
      assert Floki.attribute(tile, "y") === ["0"]
      assert Floki.attribute(tile, "width") === ["1"]
      assert Floki.attribute(tile, "height") === ["1"]
    end

    test "should have 4 tiles at zoom 1" do
      rendered = component(zoom: 1)
      {:ok, document} = Floki.parse_document(rendered)
      tiles = Floki.find(document, "image")
      assert length(tiles) === 4

      tiles
      |> Enum.with_index()
      |> Enum.each(fn({tile, index}) ->
        [x] =  Floki.attribute(tile, "x") |> Enum.map(&String.to_integer/1)
        [y] = Floki.attribute(tile, "y") |> Enum.map(&String.to_integer/1)
        assert x === div(index, 2), "tile's x should be the index divided by 2"
        assert y === rem(index, 2), "tile's y should be the modulo of the index and 2"
        assert Floki.attribute(tile, "width") === ["1"], "tile width should always be 1"
        assert Floki.attribute(tile, "height") === ["1"], "tile height should always be 1"
      end)
    end

    property "tile layer" do
      check all latitude <- StreamData.float(min: -89.9999, max: 89.9999),
        longitude <- StreamData.float(min: -179.9999, max: 179.9999),
        zoom <- StreamData.integer(1..18),
        width <- StreamData.integer(),
        height <- StreamData.integer() do

        tiles = LiveMap.tiles(latitude, longitude, zoom, width, height)
        rendered = component(
          latitude: latitude,
          longitude: longitude,
          zoom: zoom,
          width: width,
          height: height,
        )

        {:ok, document} = Floki.parse_document(rendered)

        [viewbox] = Floki.attribute(document, "svg", "viewbox")
        assert viewbox === LiveMap.viewbox(tiles)

        images = Floki.find(document, "image")
        assert length(images) === length(tiles)

        images
        |> Enum.with_index()
        |> Enum.each(fn({image, index}) ->
          tile = Enum.at(tiles, index)
          [x] =  Floki.attribute(image, "x") |> Enum.map(&String.to_integer/1)
          [y] = Floki.attribute(image, "y") |> Enum.map(&String.to_integer/1)
          assert x === tile.x, "image's x at #{x} should be the same as tile's x at #{tile.x}"
          assert y === tile.y, "image's y at #{y} should be the same as tile's y at #{tile.y}"
          assert Floki.attribute(image, "width") === ["1"], "image width should always be 1"
          assert Floki.attribute(image, "height") === ["1"], "image height should always be 1"
        end)
      end
    end

  end

  defp component(assigns \\ []) do
    assigns = Keyword.merge([id: "live-map"], assigns)
    render_component(LiveMap, assigns)
  end
end
