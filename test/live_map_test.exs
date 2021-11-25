defmodule LiveMapTest do
  use ExUnit.Case, async: true
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

    test "should have 1 tile covering the whole wold at zoom 0" do
      rendered = component(zoom: 0)
      {:ok, document} = Floki.parse_document(rendered)
      assert [tile] = Floki.find(document, "image")
      assert Floki.attribute(tile, "x") === ["0"]
      assert Floki.attribute(tile, "y") === ["0"]
      assert Floki.attribute(tile, "width") === ["256px"]
      assert Floki.attribute(tile, "height") === ["256px"]
    end

    test "should have 4 tiles at zoom 1" do
      rendered = component(zoom: 1)
      {:ok, document} = Floki.parse_document(rendered)
      tiles = Floki.find(document, "image")
      assert length(tiles) === 4
    end

  end

  defp component(assigns \\ []) do
    assigns = Keyword.merge([id: "live-map"], assigns)
    render_component(LiveMap, assigns)
  end
end
