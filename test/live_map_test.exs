defmodule LiveMapTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  doctest LiveMap

  import Phoenix.ConnTest
  import Phoenix.Component
  import Phoenix.LiveViewTest
  @endpoint LiveMapTestApp.Endpoint

  alias LiveMap.Tile

  describe "component" do
    test "renders component as an SVG" do
      assert component() =~ "</svg>"
    end

    test "use the component ID as DOM ID" do
      assert component(id: "my-awesome-map") =~ "<svg id=\"my-awesome-map\""
    end

    test "supports setting class on the root svg" do
      assert component(class: "aspect-video") =~ "class=\"aspect-video\""
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

    test "renders custom HTML through unified map control slots" do
      rendered = component_with_map_controls()

      {:ok, document} = Floki.parse_document(rendered)

      for action <- ~w(pan-up pan-left pan-right pan-down zoom-in zoom-out) do
        assert [control] = Floki.find(document, "[data-live-map-control='#{action}']")
        assert [_body] = Floki.find(document, "[data-map-control-body='#{action}']")
        assert Floki.attribute(control, "aria-label") === [map_control_label(action)]
      end

      [pan_right] = Floki.find(document, "[data-live-map-control='pan-right']")
      assert Floki.attribute(pan_right, "data-live-map-control-step") === ["2"]
    end

    test "lays out pan controls as a D-pad with a compact zoom stack" do
      {:ok, document} = component_with_map_controls() |> Floki.parse_document()
      [group] = Floki.find(document, "g.live-map-controls")

      assert Floki.attribute(group, "transform") === ["translate(212,14)"]

      expected_positions = %{
        "pan-up" => "translate(24,0)",
        "pan-left" => "translate(0,24)",
        "pan-right" => "translate(48,24)",
        "pan-down" => "translate(24,48)",
        "zoom-in" => "translate(24,72)",
        "zoom-out" => "translate(24,96)"
      }

      for {action, transform} <- expected_positions do
        [control] = Floki.find(group, "[data-live-map-control='#{action}']")
        assert Floki.attribute(control, "transform") === [transform]
      end
    end

    test "keeps zoom-only controls in the existing narrow bottom-right position" do
      {:ok, document} = component_with_zoom_only_controls() |> Floki.parse_document()
      [group] = Floki.find(document, "g.live-map-controls")

      assert Floki.attribute(group, "transform") === ["translate(260,86)"]

      assert Floki.attribute(
               hd(Floki.find(group, "[data-live-map-control='zoom-in']")),
               "transform"
             ) === [
               "translate(0,0)"
             ]

      assert Floki.attribute(
               hd(Floki.find(group, "[data-live-map-control='zoom-out']")),
               "transform"
             ) === [
               "translate(0,24)"
             ]
    end

    test "supports deprecated zoom slots and lets matching map controls take precedence" do
      rendered = component_with_legacy_zoom_controls()
      {:ok, document} = Floki.parse_document(rendered)

      assert [_new_zoom_in] = Floki.find(document, "[data-map-control-body='new-zoom-in']")

      assert [_legacy_zoom_out] =
               Floki.find(document, "[data-map-control-body='legacy-zoom-out']")

      assert Floki.find(document, "[data-map-control-body='legacy-zoom-in']") === []
    end

    test "rejects invalid and duplicate map control declarations" do
      assert_raise ArgumentError, ~r/map_control action must be one of/, fn ->
        LiveMap.render(%{id: "map", map_control: [%{action: "rotate-left", step: 1}]})
      end

      assert_raise ArgumentError, ~r/map_control step must be a positive integer/, fn ->
        LiveMap.render(%{id: "map", map_control: [%{action: "zoom-in", step: 0}]})
      end

      assert_raise ArgumentError, ~r/duplicate map_control action: "zoom-in"/, fn ->
        LiveMap.render(%{
          id: "map",
          map_control: [
            %{action: "zoom-in", step: 1},
            %{action: "zoom-in", step: 2}
          ]
        })
      end
    end

    test "renders markers inside a dedicated marker layer" do
      rendered =
        component_with_markers([
          %{id: "center", latitude: 0, longitude: 0, label: "Center"},
          %{id: "east", latitude: 0, longitude: 10, label: "East"}
        ])

      {:ok, document} = Floki.parse_document(rendered)
      assert [_marker_layer] = Floki.find(document, "svg.live-map-markers")
      markers = Floki.find(document, "g.live-map-marker")

      assert length(markers) === 2
    end

    test "projects marker slots into map coordinates" do
      rendered =
        component_with_markers([
          %{id: "center", latitude: 0, longitude: 0, label: "Center marker"}
        ])

      {:ok, document} = Floki.parse_document(rendered)
      [marker] = Floki.find(document, "#live-map-marker-center")

      assert Floki.attribute(marker, "style") === [
               "transform: translate(150.0px, 75.0px) scale(1.0);"
             ]
    end

    test "uses marker labels for accessibility and custom HTML slot bodies without :let" do
      rendered =
        component_with_markers(
          [
            %{id: "center", latitude: 0, longitude: 0, label: "Center marker"}
          ],
          marker_body: :html
        )

      {:ok, document} = Floki.parse_document(rendered)
      [marker] = Floki.find(document, "#live-map-marker-center")
      [html_marker] = Floki.find(marker, "div[data-html-marker='center']")

      assert Floki.attribute(marker, "data-live-map-marker-label") === ["Center marker"]
      assert Floki.attribute(marker, "data-live-map-marker-title") === ["Center marker"]
      assert Floki.find(marker, "title") |> Floki.text() === "Center marker"
      assert Floki.text(html_marker) |> String.trim() === "Center marker"
    end

    test "wraps HTML marker bodies in a foreignObject" do
      rendered =
        component_with_markers(
          [
            %{id: "center", latitude: 0, longitude: 0, label: "Center marker"}
          ],
          marker_body: :html
        )

      {:ok, document} = Floki.parse_document(rendered)
      [marker] = Floki.find(document, "#live-map-marker-center")

      assert [_foreign_object] = Floki.find(marker, "foreignobject")
      assert [_html_marker] = Floki.find(marker, "div[data-html-marker='center']")
    end

    test "falls back to a default marker pin with an accessible label when the slot body is empty" do
      rendered =
        component_with_markers(
          [
            %{id: "center", latitude: 0, longitude: 0, label: "Center marker"}
          ],
          marker_body: :none
        )

      {:ok, document} = Floki.parse_document(rendered)
      [marker] = Floki.find(document, "#live-map-marker-center")

      assert [_pin] = Floki.find(marker, "path.live-map-marker-pin")
      assert [_pin_center] = Floki.find(marker, "circle.live-map-marker-pin-center")
      assert Floki.find(marker, "title") |> Floki.text() === "Center marker"
    end

    test "falls back to the default marker pin when the slot body is blank" do
      rendered =
        component_with_markers(
          [
            %{id: "center", latitude: 0, longitude: 0, label: "Center marker"}
          ],
          marker_body: :blank
        )

      {:ok, document} = Floki.parse_document(rendered)
      [marker] = Floki.find(document, "#live-map-marker-center")

      assert [_pin] = Floki.find(marker, "path.live-map-marker-pin")
      refute Floki.find(marker, "foreignobject") |> Enum.any?()
    end

    test "renders projected polylines inside a dedicated shape layer" do
      rendered =
        component_with_shapes([
          %{id: "route", points: [%{latitude: 0, longitude: 0}, %{latitude: 0, longitude: 10}]}
        ])

      {:ok, document} = Floki.parse_document(rendered)

      assert [_shape_layer] = Floki.find(document, "svg.live-map-shapes")
      [polyline] = Floki.find(document, "polyline#live-map-polyline-route")
      assert Floki.attribute(polyline, "points") === ["150.0,75.0 157.11,75.0"]
    end

    test "renders projected polygons inside a dedicated shape layer" do
      rendered =
        component_with_shapes([],
          polygons: [
            %{
              id: "district",
              points: [
                %{latitude: 0, longitude: 0},
                %{latitude: 0, longitude: 10},
                %{latitude: 10, longitude: 10}
              ]
            }
          ]
        )

      {:ok, document} = Floki.parse_document(rendered)

      [polygon] = Floki.find(document, "polygon#live-map-polygon-district")

      assert Floki.attribute(polygon, "points") === [
               "150.0,75.0 157.11,75.0 157.11,67.85"
             ]
    end
  end

  describe "tiles" do
    test "uses the raster rendering type by default" do
      rendered = component(zoom: 0)

      assert rendered =~ "https://tile.openstreetmap.org/0/0/0.png"
    end

    test "selects the built-in sources with rendering-type" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}

      assert {:ok, raster_socket} =
               LiveMap.update(
                 %{
                   id: "raster-map",
                   width: 0,
                   height: 0,
                   zoom: 0,
                   "rendering-type": "raster"
                 },
                 socket
               )

      assert raster_socket.assigns.tile_source === LiveMap.Tile.default_source()

      assert {:ok, vector_socket} =
               LiveMap.update(
                 %{
                   id: "vector-map",
                   width: 0,
                   height: 0,
                   zoom: 0,
                   "rendering-type": "vector"
                 },
                 socket
               )

      assert vector_socket.assigns.tile_source === LiveMap.Tile.default_vector_source()
    end

    test "rendering-type takes precedence over tile_source" do
      custom_source = %{url: "https://tiles.example.com/{z}/{x}/{y}.png"}
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}

      assert {:ok, updated} =
               LiveMap.update(
                 %{
                   id: "raster-map",
                   width: 0,
                   height: 0,
                   zoom: 0,
                   tile_source: custom_source,
                   "rendering-type": "raster"
                 },
                 socket
               )

      assert updated.assigns.tile_source === LiveMap.Tile.default_source()
    end

    test "rejects unsupported rendering types" do
      assert_raise ArgumentError, ~r/rendering-type must be/, fn ->
        component([{:"rendering-type", "terrain"}])
      end
    end

    test "should throw at negative zoom level" do
      assert_raise FunctionClauseError, fn ->
        component(zoom: -1)
      end
    end

    test "should have 1 tile covering the whole wold at zoom 0" do
      rendered = component(zoom: 0)
      {:ok, document} = Floki.parse_document(rendered)
      assert [_, tile | _] = Floki.find(document, "image")
      assert Floki.attribute(tile, "href") === ["https://tile.openstreetmap.org/0/0/0.png"]
      assert Floki.attribute(tile, "x") === ["22.0"]
      assert Floki.attribute(tile, "y") === ["-53.0"]
      assert Floki.attribute(tile, "width") === ["256"]
      assert Floki.attribute(tile, "height") === ["256"]
    end

    test "expands a custom raster tile source" do
      rendered =
        component(
          zoom: 1,
          tile_source: %{
            type: :raster,
            url: "https://tiles.example.com/{zoom}/{x}/{y}.png?level={z}"
          }
        )

      {:ok, document} = Floki.parse_document(rendered)
      tiles = Floki.find(document, "image")

      assert Enum.map(tiles, &Floki.attribute(&1, "href")) === [
               ["https://tiles.example.com/1/0/0.png?level=1"],
               ["https://tiles.example.com/1/0/1.png?level=1"],
               ["https://tiles.example.com/1/1/0.png?level=1"],
               ["https://tiles.example.com/1/1/1.png?level=1"]
             ]
    end

    test "should have 4 tiles at zoom 1" do
      rendered = component(zoom: 1)
      {:ok, document} = Floki.parse_document(rendered)
      tiles = Floki.find(document, "image")
      assert length(tiles) === 4

      tiles
      |> Enum.with_index()
      |> Enum.each(fn {tile, index} ->
        [x] = Floki.attribute(tile, "x") |> Enum.map(&String.to_float/1)
        [y] = Floki.attribute(tile, "y") |> Enum.map(&String.to_float/1)
        assert x === div(index, 2) * 256 - 106.0, "tile's x should be relative to min_x"
        assert y === rem(index, 2) * 256 - 181.0, "tile's y should be relative to min_y"
        assert Floki.attribute(tile, "width") === ["256"], "tile width should always be 256"
        assert Floki.attribute(tile, "height") === ["256"], "tile height should always be 256"
      end)
    end

    property "tile layer" do
      check all(
              latitude <- StreamData.float(min: -89.9999, max: 89.9999),
              longitude <- StreamData.float(min: -179.9999, max: 179.9999),
              zoom <- StreamData.integer(1..18),
              width <- StreamData.integer(1..2000),
              height <- StreamData.integer(1..2000)
            ) do
        tiles = LiveMap.tiles(latitude, longitude, zoom, width, height)

        rendered =
          component(
            latitude: latitude,
            longitude: longitude,
            zoom: zoom,
            width: width,
            height: height
          )

        {:ok, document} = Floki.parse_document(rendered)

        layer_viewboxes = Floki.attribute(document, "svg > svg", "viewbox")

        assert Enum.uniq(layer_viewboxes) === [
                 "0 0 #{width} #{height}"
               ]

        images = Floki.find(document, "image")
        assert length(images) === length(tiles)

        images
        |> Enum.with_index()
        |> Enum.each(fn {image, index} ->
          tile = Enum.at(tiles, index)
          [x] = Floki.attribute(image, "x") |> Enum.map(&String.to_float/1)
          [y] = Floki.attribute(image, "y") |> Enum.map(&String.to_float/1)

          center_x = LiveMap.Tile.x(longitude, zoom) * 256.0
          center_y = LiveMap.Tile.y(latitude, zoom) * 256.0
          min_x = center_x - width / 2.0
          min_y = center_y - height / 2.0

          assert_in_delta x, tile.x * 256 - min_x, 1.0e-5
          assert_in_delta y, tile.y * 256 - min_y, 1.0e-5
          assert Floki.attribute(image, "width") === ["256"], "image width should always be 256"
          assert Floki.attribute(image, "height") === ["256"], "image height should always be 256"
        end)
      end
    end
  end

  describe "map controls" do
    setup do
      [conn: Phoenix.ConnTest.build_conn()]
    end

    test "in by clicking Zoom In button", %{conn: conn} do
      {:ok, view, rendered} = live(conn, "/")
      {:ok, document} = Floki.parse_document(rendered)
      # There is only 1 tile at zoom level 0
      assert [_, _tile | _] = Floki.find(document, "image")

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
      assert [_, _tile | _] = Floki.find(document, "image")
    end

    test "pans by clicking a directional control", %{conn: conn} do
      {:ok, view, rendered} = live(conn, "/")
      {:ok, initial_document} = Floki.parse_document(rendered)

      initial_x =
        initial_document
        |> Floki.find("image")
        |> hd()
        |> Floki.attribute("x")

      rendered =
        view
        |> element("#live-map [role=\"button\"][aria-label=\"Pan Right\"]")
        |> render_click()

      {:ok, updated_document} = Floki.parse_document(rendered)

      updated_x =
        updated_document
        |> Floki.find("image")
        |> hd()
        |> Floki.attribute("x")

      refute updated_x === initial_x
    end

    test "by pressing Enter", %{conn: conn} do
      {:ok, view, rendered} = live(conn, "/")
      {:ok, document} = Floki.parse_document(rendered)
      # There is only 1 tile at zoom level 0
      assert [_, _tile | _] = Floki.find(document, "image")

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
      assert [_, _tile | _] = Floki.find(document, "image")
    end

    test "by pressing Space", %{conn: conn} do
      {:ok, view, rendered} = live(conn, "/")
      {:ok, document} = Floki.parse_document(rendered)
      # There is only 1 tile at zoom level 0
      assert [_, _tile | _] = Floki.find(document, "image")

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
      assert [_, _tile | _] = Floki.find(document, "image")
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
      assert [_, _ | _] = Floki.find(document, "image")
    end

    test "uses the server-owned step for zoom and clamps at zero" do
      socket = prepared_map_socket(zoom: 1, map_control: [%{action: "zoom-in", step: 2}])

      assert {:noreply, zoomed_in} =
               LiveMap.handle_event("map_control", %{"action" => "zoom-in"}, socket)

      assert zoomed_in.assigns.zoom === 3

      socket = prepared_map_socket(zoom: 1, map_control: [%{action: "zoom-out", step: 2}])

      assert {:noreply, zoomed_out} =
               LiveMap.handle_event("map_control", %{"action" => "zoom-out"}, socket)

      assert zoomed_out.assigns.zoom === 0
    end

    test "defaults step to one and ignores unknown or tampered actions" do
      socket = prepared_map_socket(zoom: 1, map_control: [%{action: "zoom-in"}])

      assert {:noreply, zoomed} =
               LiveMap.handle_event("map_control", %{"action" => "zoom-in"}, socket)

      assert zoomed.assigns.zoom === 2

      assert {:noreply, unchanged} =
               LiveMap.handle_event("map_control", %{"action" => "pan-right"}, socket)

      assert unchanged === socket

      assert {:noreply, unchanged} = LiveMap.handle_event("map_control", %{}, socket)
      assert unchanged === socket
    end

    test "reports control-driven bounds changes through the server callback" do
      test_pid = self()

      socket =
        prepared_map_socket(
          width: 512,
          zoom: 2,
          map_control: [%{action: "pan-right"}],
          on_bounds_changed: fn view -> send(test_pid, {:bounds_changed, view}) end
        )

      assert {:noreply, _updated} =
               LiveMap.handle_event("map_control", %{"action" => "pan-right"}, socket)

      assert_receive {:bounds_changed,
                      %{
                        action: "pan-right",
                        center: {latitude, longitude},
                        id: "live-map",
                        zoom: 2
                      }}

      assert_in_delta latitude, 0.0, 1.0e-10
      assert_in_delta longitude, 90.0, 1.0e-10
    end

    test "does not report unchanged views and rejects an invalid callback" do
      test_pid = self()

      socket =
        prepared_map_socket(
          zoom: 0,
          map_control: [%{action: "zoom-out"}],
          on_bounds_changed: fn view -> send(test_pid, {:bounds_changed, view}) end
        )

      assert {:noreply, unchanged} =
               LiveMap.handle_event("map_control", %{"action" => "zoom-out"}, socket)

      assert unchanged === socket
      refute_receive {:bounds_changed, _view}

      invalid =
        prepared_map_socket(
          map_control: [%{action: "zoom-in"}],
          on_bounds_changed: :invalid
        )

      assert_raise ArgumentError, ~r/on_bounds_changed must be a function/, fn ->
        LiveMap.handle_event("map_control", %{"action" => "zoom-in"}, invalid)
      end
    end

    test "accepts legacy Spacebar and ignores non-activation keys before dispatch" do
      socket = prepared_map_socket(zoom: 1, map_control: [%{action: "zoom-in", step: 2}])

      assert {:noreply, zoomed} =
               LiveMap.handle_event(
                 "map_control",
                 %{"action" => "zoom-in", "key" => "Spacebar"},
                 socket
               )

      assert zoomed.assigns.zoom === 3

      assert {:noreply, unchanged} =
               LiveMap.handle_event(
                 "map_control",
                 %{"action" => "zoom-in", "key" => "ArrowUp"},
                 socket
               )

      assert unchanged === socket
    end

    test "pans one half-viewport step in every direction" do
      expected = %{
        "pan-up" => {Tile.latitude(1.5, 2), 0.0},
        "pan-right" => {0.0, 90.0},
        "pan-down" => {Tile.latitude(2.5, 2), 0.0},
        "pan-left" => {0.0, -90.0}
      }

      for {action, {expected_latitude, expected_longitude}} <- expected do
        socket =
          prepared_map_socket(
            width: 512,
            height: 256,
            zoom: 2,
            map_control: [%{action: action}]
          )

        assert {:noreply, updated} =
                 LiveMap.handle_event("map_control", %{"action" => action}, socket)

        assert_in_delta updated.assigns.latitude, expected_latitude, 1.0e-10
        assert_in_delta updated.assigns.longitude, expected_longitude, 1.0e-10
      end
    end

    test "multiplies pan distance by step at the current viewport and zoom" do
      socket =
        prepared_map_socket(
          width: 300,
          height: 200,
          zoom: 3,
          map_control: [%{action: "pan-right", step: 2}]
        )

      assert {:noreply, updated} =
               LiveMap.handle_event("map_control", %{"action" => "pan-right"}, socket)

      expected_x = Tile.x(0.0, 3) + 2 * (300 / 2.0) / 256.0
      assert_in_delta updated.assigns.longitude, Tile.longitude(expected_x, 3), 1.0e-10
    end

    test "wraps horizontally and clamps vertical panning to Web Mercator" do
      horizontal =
        prepared_map_socket(
          center: {0, 170},
          width: 512,
          zoom: 2,
          map_control: [%{action: "pan-right"}]
        )

      assert {:noreply, wrapped} =
               LiveMap.handle_event("map_control", %{"action" => "pan-right"}, horizontal)

      assert_in_delta wrapped.assigns.longitude, 260.0, 1.0e-10

      for {action, expected_latitude} <- [
            {"pan-up", Tile.latitude(0, 0)},
            {"pan-down", Tile.latitude(1, 0)}
          ] do
        vertical =
          prepared_map_socket(
            height: 1024,
            zoom: 0,
            map_control: [%{action: action, step: 2}]
          )

        assert {:noreply, clamped} =
                 LiveMap.handle_event("map_control", %{"action" => action}, vertical)

        assert_in_delta clamped.assigns.latitude, expected_latitude, 1.0e-10
      end
    end

    test "reprojects markers and shapes after panning" do
      socket =
        prepared_map_socket(
          width: 512,
          height: 256,
          zoom: 2,
          map_control: [%{action: "pan-right"}],
          marker: [%{id: "center", position: {0, 0}, title: "Center"}],
          polyline: [%{id: "line", points: [%{latitude: 0, longitude: 0}]}],
          polygon: [%{id: "area", points: [%{latitude: 0, longitude: 0}]}]
        )

      assert [%{x: 256.0}] = socket.assigns.marker_overlays

      assert Enum.all?(socket.assigns.shape_overlays, fn shape ->
               shape.points == [{256.0, 128.0}]
             end)

      assert {:noreply, updated} =
               LiveMap.handle_event("map_control", %{"action" => "pan-right"}, socket)

      assert [%{x: marker_x}] = updated.assigns.marker_overlays
      assert_in_delta marker_x, 0.0, 1.0e-10

      assert Enum.all?(updated.assigns.shape_overlays, fn shape ->
               shape.points == [{0.0, 128.0}]
             end)

      refute updated.assigns.tiles === socket.assigns.tiles
    end
  end

  describe "coordinate updates propagate to LiveMap component" do
    test "accepts a Google-style center and gives it precedence over legacy coordinates" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}

      assert {:ok, updated} =
               LiveMap.update(
                 %{
                   id: "test-map",
                   width: 0,
                   height: 0,
                   center: "10.3458, 107.0705",
                   latitude: 1,
                   longitude: 2,
                   zoom: 1
                 },
                 socket
               )

      assert updated.assigns.latitude === 10.3458
      assert updated.assigns.longitude === 107.0705
    end

    test "accepts center tuples and LatLng-style maps" do
      for center <- [{10, 20}, %{lat: 10, lng: 20}, %{"lat" => 10, "lng" => 20}] do
        rendered = component(center: center, zoom: 1)
        assert rendered =~ "<svg"
      end
    end

    test "rejects an invalid center" do
      assert_raise ArgumentError, ~r/invalid center/, fn ->
        component(center: "north,west")
      end
    end

    test "viewBox updates when coordinates change" do
      # Render the component at initial coordinates (0, 0)
      initial_html =
        render_component(LiveMap,
          id: "test-map",
          width: 300,
          height: 150,
          latitude: 0.0,
          longitude: 0.0,
          zoom: 1
        )

      {:ok, initial_doc} = Floki.parse_document(initial_html)
      initial_viewboxes = get_layer_viewboxes(initial_doc)

      # Render the component at updated coordinates
      updated_html =
        render_component(LiveMap,
          id: "test-map",
          width: 300,
          height: 150,
          latitude: 10.3458,
          longitude: 107.0705,
          zoom: 1
        )

      {:ok, updated_doc} = Floki.parse_document(updated_html)
      updated_viewboxes = get_layer_viewboxes(updated_doc)

      # The viewBox should reflect the new coordinates
      # The viewBox should be static, but tile coordinates should change
      assert initial_viewboxes == updated_viewboxes,
             "viewBox should remain static."

      initial_tiles = Floki.find(initial_doc, "image") |> Enum.map(&Floki.attribute(&1, "x"))
      updated_tiles = Floki.find(updated_doc, "image") |> Enum.map(&Floki.attribute(&1, "x"))
      assert initial_tiles != updated_tiles, "Tiles should move when coordinates change"
    end

    test "viewBox reflects correct center for given coordinates" do
      rendered =
        render_component(LiveMap,
          id: "test-map",
          width: 300,
          height: 150,
          latitude: 10.3458,
          longitude: 107.0705,
          zoom: 14
        )

      {:ok, document} = Floki.parse_document(rendered)
      viewboxes = get_layer_viewboxes(document)

      # All layer viewboxes should use the same viewbox
      assert length(Enum.uniq(viewboxes)) == 1,
             "All layers should share the same viewBox, got: #{inspect(viewboxes)}"

      # The viewBox should correspond to the given coordinates
      expected_viewbox = "0 0 300 150"
      assert hd(viewboxes) == expected_viewbox
    end

    test "update/2 properly marks assigns as changed when coordinates change" do
      # This test directly exercises the update/2 path to verify that
      # __changed__ tracking is correct after coordinate updates.

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{}
        },
        endpoint: @endpoint
      }

      # First update with initial coordinates
      {:ok, socket1} =
        LiveMap.update(
          %{
            id: "test-map",
            width: 300,
            height: 150,
            latitude: 0.0,
            longitude: 0.0,
            zoom: 1
          },
          socket
        )

      # Clear __changed__ to simulate the end of a render cycle
      socket1 = %{socket1 | assigns: Map.put(socket1.assigns, :__changed__, %{})}

      # Second update with changed coordinates
      {:ok, socket2} =
        LiveMap.update(
          %{
            id: "test-map",
            width: 300,
            height: 150,
            latitude: 10.3458,
            longitude: 107.0705,
            zoom: 1
          },
          socket1
        )

      # Verify coordinates were actually updated
      assert socket2.assigns[:latitude] == 10.3458, "latitude should be updated"
      assert socket2.assigns[:longitude] == 107.0705, "longitude should be updated"

      # Verify __changed__ includes the changed keys
      changed = socket2.assigns[:__changed__]
      assert changed != nil, "__changed__ should be present"

      assert Map.has_key?(changed, :latitude),
             "latitude should be marked as changed, __changed__ = #{inspect(changed)}"

      assert Map.has_key?(changed, :longitude),
             "longitude should be marked as changed, __changed__ = #{inspect(changed)}"
    end
  end

  defp component(assigns \\ []) do
    assigns = Keyword.merge([id: "live-map"], assigns)
    render_component(LiveMap, assigns)
  end

  defp map_control_label(action) do
    action
    |> String.split("-")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp component_with_markers(markers, assigns \\ []) do
    defaults = %{
      id: "live-map",
      width: 300,
      height: 150,
      latitude: 0,
      longitude: 0,
      zoom: 0,
      markers: markers,
      marker_body: :html
    }

    assigns = Map.merge(defaults, Enum.into(assigns, %{}))

    render_component(
      fn assigns ->
        ~H"""
        <.live_component
          module={LiveMap}
          id={@id}
          width={@width}
          height={@height}
          center={{@latitude, @longitude}}
          zoom={@zoom}
        >
          <:marker
            :if={@marker_body == :html}
            :for={marker <- @markers}
            id={marker.id}
            position={{marker.latitude, marker.longitude}}
            title={marker.label}
          >
            <div data-html-marker={marker.id} class="rounded-full bg-sky-600 px-3 py-1 text-white">
              {marker.label}
            </div>
          </:marker>

          <:marker
            :if={@marker_body == :none}
            :for={marker <- @markers}
            id={marker.id}
            position={{marker.latitude, marker.longitude}}
            title={marker.label}
          />

          <:marker
            :if={@marker_body == :blank}
            :for={marker <- @markers}
            id={marker.id}
            position={{marker.latitude, marker.longitude}}
            title={marker.label}
          >
          </:marker>
        </.live_component>
        """
      end,
      assigns
    )
  end

  defp component_with_map_controls(assigns \\ %{}) do
    render_component(
      fn assigns ->
        ~H"""
        <.live_component module={LiveMap} id="live-map" width={300} height={150} zoom={0}>
          <:map_control action="pan-up">
            <span data-map-control-body="pan-up">↑</span>
          </:map_control>

          <:map_control action="pan-left">
            <span data-map-control-body="pan-left">←</span>
          </:map_control>

          <:map_control action="pan-right" step={2}>
            <span data-map-control-body="pan-right">→</span>
          </:map_control>

          <:map_control action="pan-down">
            <span data-map-control-body="pan-down">↓</span>
          </:map_control>

          <:map_control action="zoom-in">
            <span data-map-control-body="zoom-in">+</span>
          </:map_control>

          <:map_control action="zoom-out">
            <span data-map-control-body="zoom-out">-</span>
          </:map_control>
        </.live_component>
        """
      end,
      assigns
    )
  end

  defp component_with_zoom_only_controls(assigns \\ %{}) do
    render_component(
      fn assigns ->
        ~H"""
        <.live_component module={LiveMap} id="live-map" width={300} height={150} zoom={0}>
          <:map_control action="zoom-in">+</:map_control>
          <:map_control action="zoom-out">-</:map_control>
        </.live_component>
        """
      end,
      assigns
    )
  end

  defp component_with_legacy_zoom_controls(assigns \\ %{}) do
    render_component(
      fn assigns ->
        ~H"""
        <.live_component module={LiveMap} id="live-map" width={300} height={150} zoom={0}>
          <:zoom_in>
            <span data-map-control-body="legacy-zoom-in">+</span>
          </:zoom_in>

          <:zoom_out>
            <span data-map-control-body="legacy-zoom-out">-</span>
          </:zoom_out>

          <:map_control action="zoom-in">
            <span data-map-control-body="new-zoom-in">New +</span>
          </:map_control>
        </.live_component>
        """
      end,
      assigns
    )
  end

  defp prepared_map_socket(assigns) do
    defaults = %{
      id: "live-map",
      width: 300,
      height: 150,
      center: {0, 0},
      zoom: 0,
      map_control: [],
      marker: [],
      polyline: [],
      polygon: []
    }

    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}
    {:ok, socket} = LiveMap.update(Map.merge(defaults, Map.new(assigns)), socket)
    socket
  end

  defp component_with_shapes(polylines, assigns \\ []) do
    defaults = %{
      id: "live-map",
      width: 300,
      height: 150,
      latitude: 0,
      longitude: 0,
      zoom: 0,
      polylines: polylines,
      polygons: []
    }

    assigns = Map.merge(defaults, Enum.into(assigns, %{}))

    render_component(
      fn assigns ->
        ~H"""
        <.live_component
          module={LiveMap}
          id={@id}
          width={@width}
          height={@height}
          latitude={@latitude}
          longitude={@longitude}
          zoom={@zoom}
        >
          <:polyline
            :for={polyline <- @polylines}
            id={polyline.id}
            points={polyline.points}
          />

          <:polygon
            :for={polygon <- @polygons}
            id={polygon.id}
            points={polygon.points}
          />
        </.live_component>
        """
      end,
      assigns
    )
  end

  defp get_layer_viewboxes(document) do
    Floki.find(document, "svg > svg")
    |> Enum.flat_map(&Floki.attribute(&1, "viewbox"))
  end

  test "viewbox/1 returns the correct viewbox for a list of tiles" do
    assert LiveMap.viewbox([]) == "0 0 0 0"
    assert LiveMap.viewbox([%{x: 0, y: 0}]) == "0 0 256 256"

    assert LiveMap.viewbox([
             %{x: 0, y: 0},
             %{x: 0, y: 1},
             %{x: 1, y: 0},
             %{x: 1, y: 1}
           ]) == "0 0 512 512"
  end

  test "viewbox/5 returns the correct viewbox for latitude, longitude, zoom, width, height" do
    assert LiveMap.viewbox(0.0, 0.0, 0, 800, 600) == "-272.0 -172.0 800 600"
  end

  test "update handles async_ref tile layer result properly" do
    socket = %Phoenix.LiveView.Socket{assigns: %{async_ref: :ref, __changed__: %{}}}

    assert {:ok, new_socket} =
             LiveMap.update(
               %{tile_layer_result: %{defs: [], tiles: []}, async_ref: :ref},
               socket
             )

    assert new_socket.assigns.tile_layer == %{defs: [], tiles: []}

    assert {:ok, socket2} =
             LiveMap.update(
               %{tile_layer_result: %{defs: [], tiles: []}, async_ref: :old_ref},
               socket
             )

    assert socket2 == socket
  end

  test "update merges matching vector tile deltas and ignores stale deltas" do
    loading_tile = %{
      type: :svg_use,
      state: "loading",
      display_tile: "2/1/1",
      z: 2,
      x: 256,
      y: 256,
      width: 256,
      height: 256,
      view_box: "0 0 256 256",
      def_id: "loading-2/1/1",
      source_tile: "2/1/1"
    }

    ready_tile = %{
      loading_tile
      | state: "ready",
        view_box: "0 0 1 1",
        def_id: "vector-2-1-1"
    }

    delta = %{
      definition: %{
        id: "vector-2-1-1",
        content: Phoenix.HTML.raw("<svg id=\"vector-2-1-1\"></svg>")
      },
      tiles: [ready_tile]
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        async_ref: :current,
        tile_layer: %{defs: [], tiles: [loading_tile]},
        __changed__: %{}
      }
    }

    assert {:ok, updated} =
             LiveMap.update(%{tile_layer_delta: delta, async_ref: :current}, socket)

    assert [%{state: "ready", display_tile: "2/1/1"}] = updated.assigns.tile_layer.tiles
    assert updated.assigns.tile_layer.cached_tiles["2/1/1"].state == "ready"

    assert [definition] = updated.assigns.tile_layer.defs
    assert definition |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary() =~ "vector-2-1-1"

    assert {:ok, unchanged} =
             LiveMap.update(%{tile_layer_delta: delta, async_ref: :stale}, socket)

    assert unchanged == socket
  end

  test "update retains late vector tiles from the same source and style after panning" do
    loading_tile = %{
      type: :svg_use,
      state: "loading",
      display_tile: "2/2/1",
      z: 2,
      x: 512,
      y: 256,
      width: 256,
      height: 256,
      view_box: "0 0 256 256",
      def_id: "loading-2/2/1",
      source_tile: "2/2/1"
    }

    late_tile = %{
      loading_tile
      | state: "ready",
        display_tile: "2/1/1",
        x: 256,
        view_box: "0 0 1 1",
        def_id: "vector-2-1-1"
    }

    delta = %{
      definition: %{
        id: "vector-2-1-1",
        content: Phoenix.HTML.raw("<svg id=\"vector-2-1-1\"></svg>")
      },
      tiles: [late_tile]
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        async_ref: :current_pan,
        tile_cache_context: {:source, "css"},
        tile_layer: %{defs: [], tiles: [loading_tile]},
        __changed__: %{}
      }
    }

    assert {:ok, updated} =
             LiveMap.update(
               %{
                 tile_layer_delta: delta,
                 async_ref: :previous_pan,
                 tile_cache_context: {:source, "css"}
               },
               socket
             )

    assert updated.assigns.tile_layer.tiles == [loading_tile]
    assert updated.assigns.tile_layer.cached_tiles["2/1/1"].state == "ready"
  end

  test "renders cached parent content instead of a spinner for loading child tiles" do
    placeholder_tile = %{
      type: :svg_use,
      state: "loading",
      placeholder: true,
      fallback_tile: "1/0/0",
      display_tile: "2/1/1",
      z: 2,
      x: 256,
      y: 256,
      width: 256,
      height: 256,
      view_box: "0.5 0.5 0.5 0.5",
      def_id: "parent-definition",
      source_tile: "2/1/1"
    }

    html =
      LiveMap.live_map(%{
        id: "cached-map",
        class: nil,
        title: "",
        width: 256,
        height: 256,
        zoom: 2,
        min_x: 256,
        min_y: 256,
        style: [],
        map_controls: [],
        zoom_in: [],
        zoom_out: [],
        myself: nil,
        shape_overlays: [],
        marker_overlays: [],
        tile_layer: %{
          defs: [Phoenix.HTML.raw("<svg id=\"parent-definition\"></svg>")],
          tiles: [placeholder_tile]
        }
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ ~s(data-live-map-tile-placeholder="parent")
    assert html =~ ~s(data-live-map-fallback-tile="1/0/0")
    assert html =~ ~s(<use href="#parent-definition")
    refute html =~ "animateTransform"
  end

  test "update turns unfinished tiles into errors when vector streaming completes" do
    tile = %{
      type: :svg_use,
      state: "loading",
      display_tile: "0/0/0",
      z: 0,
      x: 0,
      y: 0,
      width: 256,
      height: 256,
      view_box: "0 0 256 256",
      def_id: "loading-0/0/0",
      source_tile: "0/0/0"
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        async_ref: :current,
        tile_layer: %{defs: [], tiles: [tile]},
        __changed__: %{}
      }
    }

    assert {:ok, updated} =
             LiveMap.update(%{tile_layer_complete: true, async_ref: :current}, socket)

    assert [%{state: "error", error_reason: "task-exit"}] = updated.assigns.tile_layer.tiles
  end

  test "renders MVT source async" do
    html =
      render_component(LiveMap,
        id: "mvt-map",
        tile_source: %{type: :mvt, url: "http://localhost/{z}/{x}/{y}.mvt"}
      )

    assert html =~ "data-live-map-tile-state=\"loading\""
  end
end
