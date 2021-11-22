defmodule LiveMapTest do
  use ExUnit.Case
  doctest LiveMap

  use ExUnit.Case
  import Phoenix.LiveViewTest

  describe "container" do

    test "renders component as an SVG" do
      component = render_component(LiveMap, id: "live-map")
      assert component =~ "</svg>"
    end

    test "contains a <style> descendant" do
      component = render_component(LiveMap, id: "live-map")
      assert component =~ "</style>"
    end

    test "supports setting width" do
      component = render_component(LiveMap, id: "live-map", width: 300)
      assert component =~ "width=\"300\""
    end

    test "supports setting height" do
      component = render_component(LiveMap, id: "live-map", height: 150)
      assert component =~ "height=\"150\""
    end

    test "supports setting title as <title>" do
      component = render_component(LiveMap, id: "live-map", title: "Awesome Live Map")
      assert component =~ "<title>Awesome Live Map</title>"
    end

  end
end
