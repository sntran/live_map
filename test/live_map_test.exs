defmodule LiveMapTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  doctest LiveMap

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint LiveMapTestApp.Endpoint

  describe "component" do

    test "renders component as an SVG" do
      assert component() =~ "</svg>"
    end

    test "use the component ID as DOM ID" do
      assert component(id: "my-awesome-map") =~ "<svg id=\"my-awesome-map\""
    end

    test "contains a <style> descendant" do
      assert component() =~ "</style>"
    end

    test "supports setting width" do
      assert component(width: 300) =~ "width=\"300\""
    end

    test "supports setting width as string" do
      assert component(width: "300") =~ "width=\"300\""
    end

    test "supports setting height" do
      assert component(height: 150) =~ "height=\"150\""
    end

    test "supports setting height as string" do
      assert component(height: "150") =~ "height=\"150\""
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

  describe "zoom" do

    setup do
      [conn: Phoenix.ConnTest.build_conn()]
    end

    test "in by clicking Zoom In button", %{conn: conn} do
      {:ok, view, rendered} = live(conn, "/")
      {:ok, document} = Floki.parse_document(rendered)
      # There is only 1 tile at zoom level 0
      assert [_tile] = Floki.find(document, "image")

      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom In\"]")
        |> render_click()

      {:ok, document} = Floki.parse_document(rendered)
      # There are now 4 tiles at zoom level 1
      tiles = Floki.find(document, "image")
      assert length(tiles) === 4
    end

    test "out by clicking Zoom Out button", %{conn: conn} do
      {:ok, view, _rendered} = live(conn, "/")

      # Zoom in first to go to level 1.
      view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom In\"]")
        |> render_click()

      # Clicks zoom out button to go back to level 0
      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom Out\"]")
        |> render_click()

      {:ok, document} = Floki.parse_document(rendered)
      # There is now only 1 tile.
      assert [_tile] = Floki.find(document, "image")
    end

    test "by pressing Enter", %{conn: conn} do
      {:ok, view, rendered} = live(conn, "/")
      {:ok, document} = Floki.parse_document(rendered)
      # There is only 1 tile at zoom level 0
      assert [_tile] = Floki.find(document, "image")

      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom In\"]")
        |> render_keyup(%{"key" => "Enter"})

      {:ok, document} = Floki.parse_document(rendered)
      # There are now 4 tiles at zoom level 1
      tiles = Floki.find(document, "image")
      assert length(tiles) === 4

      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom Out\"]")
        |> render_keyup(%{"key" => "Enter"})

      {:ok, document} = Floki.parse_document(rendered)
      # There is only 1 tile at zoom level 0
      assert [_tile] = Floki.find(document, "image")
    end

    test "by pressing Space", %{conn: conn} do
      {:ok, view, rendered} = live(conn, "/")
      {:ok, document} = Floki.parse_document(rendered)
      # There is only 1 tile at zoom level 0
      assert [_tile] = Floki.find(document, "image")

      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom In\"]")
        |> render_keyup(%{"key" => " "})

      {:ok, document} = Floki.parse_document(rendered)
      # There are now 4 tiles at zoom level 1
      tiles = Floki.find(document, "image")
      assert length(tiles) === 4

      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom Out\"]")
        |> render_keyup(%{"key" => " "})

      {:ok, document} = Floki.parse_document(rendered)
      # There is only 1 tile at zoom level 0
      assert [_tile] = Floki.find(document, "image")
    end

    test "ignores all other keys", %{conn: conn} do
      {:ok, view, _rendered} = live(conn, "/")

      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom In\"]")
        |> render_keyup(%{"key" => " "})

      {:ok, document} = Floki.parse_document(rendered)
      # There are 4 tiles at zoom level 1
      assert [_, _, _, _] = Floki.find(document, "image")

      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom In\"]")
        |> render_keyup(%{"key" => "ArrowUp"})

      {:ok, document} = Floki.parse_document(rendered)
      # There are still 4 tiles at zoom level 1
      assert [_, _, _, _] = Floki.find(document, "image")

      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom Out\"]")
        |> render_keyup(%{"key" => "ArrowUp"})

      {:ok, document} = Floki.parse_document(rendered)
       # There are still 4 tiles at zoom level 1
      assert [_, _, _, _] = Floki.find(document, "image")

      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Zoom Out\"]")
        |> render_keyup(%{"key" => "Enter"})

      {:ok, document} = Floki.parse_document(rendered)
       # There is now 1 tile at zoom level 0
      assert [_] = Floki.find(document, "image")
    end

  end

  defp component(assigns \\ []) do
    assigns = Keyword.merge([id: "live-map"], assigns)
    render_component(LiveMap, assigns)
  end
end
