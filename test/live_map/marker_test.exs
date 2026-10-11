defmodule LiveMap.MarkerTest do
  use ExUnit.Case, async: true

  alias LiveMap.Marker

  test "projects slot data into renderable marker overlay data" do
    marker =
      Marker.project(
        %{id: 42, position: "0,0", title: "Center marker"},
        "live-map",
        0,
        0,
        0,
        0,
        0.0
      )

    assert marker.id === "42"
    assert marker.dom_id === "live-map-marker-42"
    assert marker.title === "Center marker"
    assert marker.label === "Center marker"
    assert_in_delta marker.x, 128.0, 1.0e-6
    assert_in_delta marker.y, 128.0, 1.0e-6
    assert marker.has_body === false
  end

  test "projects polyline points into SVG point coordinates" do
    polyline =
      Marker.project_shape(
        :polyline,
        %{id: "route", points: [%{latitude: 0, longitude: 0}, %{latitude: 0, longitude: 10}]},
        "live-map",
        0,
        0,
        0,
        0,
        0.0
      )

    assert polyline.id === "route"
    assert polyline.dom_id === "live-map-polyline-route"
    assert polyline.points === [{128.0, 128.0}, {135.11, 128.0}]
    assert polyline.points_attribute === "128.0,128.0 135.11,128.0"
    assert polyline.type === :polyline
  end

  test "drops the points of a shape that are nearer than half a pixel to the point before" do
    # At zoom 0, 0.001 degree is less than 0.001 pixel.
    points =
      for i <- 0..100, do: %{latitude: 0, longitude: i * 0.001}

    polyline =
      Marker.project_shape(
        :polyline,
        %{points: points ++ [%{latitude: 0, longitude: 10}, %{latitude: 0, longitude: 10.001}]},
        "live-map",
        0,
        0,
        0,
        0,
        0.0
      )

    # The first point, the point 7.11 pixels to the east, and the last
    # point, so the line ends at its end.
    assert polyline.points === [{128.0, 128.0}, {135.11, 128.0}, {135.11, 128.0}]

    single =
      Marker.project_shape(
        :polygon,
        %{points: [%{latitude: 0, longitude: 0}]},
        "live-map",
        0,
        0,
        0,
        0,
        0.0
      )

    assert single.points === [{128.0, 128.0}]
  end

  test "uses fallback DOM ids and preserves float coordinates" do
    marker =
      Marker.project(
        %{position: %{lat: 1.5, lng: 2.5}, title: "Float marker", inner_block: fn -> nil end},
        "live-map",
        1,
        0,
        0,
        3,
        0.0
      )

    polygon =
      Marker.project_shape(
        :polygon,
        %{
          points: [
            %{latitude: 0.0, longitude: 0.0},
            %{latitude: 0.0, longitude: 1.0},
            %{latitude: 1.0, longitude: 1.0}
          ]
        },
        "live-map",
        0,
        0,
        0,
        2,
        0.0
      )

    assert marker.id === nil
    assert marker.dom_id === "live-map-marker-3"
    assert marker.has_body === true
    assert marker.latitude === 1.5
    assert marker.longitude === 2.5
    assert polygon.dom_id === "live-map-polygon-2"
  end

  test "raises on invalid marker coordinates" do
    assert_raise ArgumentError, ~r/invalid position/, fn ->
      Marker.project(%{position: "north,0", title: "Bad marker"}, "live-map", 0, 0, 0, 0, 0.0)
    end
  end

  test "keeps latitude, longitude, and label as deprecated fallbacks" do
    marker =
      Marker.project(
        %{latitude: "1.5", longitude: "2.5", label: "Legacy marker"},
        "live-map",
        1,
        0,
        0,
        0,
        0.0
      )

    assert marker.latitude === 1.5
    assert marker.longitude === 2.5
    assert marker.title === "Legacy marker"
  end

  test "prefers position and title over deprecated marker attributes" do
    marker =
      Marker.project(
        %{
          position: {1, 2},
          title: "Current marker",
          latitude: 30,
          longitude: 40,
          label: "Legacy marker"
        },
        "live-map",
        1,
        0,
        0,
        0,
        0.0
      )

    assert marker.latitude === 1.0
    assert marker.longitude === 2.0
    assert marker.title === "Current marker"
  end

  test "requires a complete position and a title" do
    assert_raise ArgumentError, ~r/marker requires position/, fn ->
      Marker.project(%{title: "Missing"}, "live-map", 0, 0, 0, 0, 0.0)
    end

    assert_raise ArgumentError, ~r/must both be provided/, fn ->
      Marker.project(%{latitude: 1, title: "Partial"}, "live-map", 0, 0, 0, 0, 0.0)
    end

    assert_raise ArgumentError, ~r/marker requires title/, fn ->
      Marker.project(%{position: {1, 2}}, "live-map", 0, 0, 0, 0, 0.0)
    end
  end

  test "projects polygon points into SVG point coordinates" do
    polygon =
      Marker.project_shape(
        :polygon,
        %{
          id: "district",
          points: [
            %{latitude: 0, longitude: 0},
            %{latitude: 0, longitude: 10},
            %{latitude: 10, longitude: 10}
          ]
        },
        "live-map",
        0,
        0,
        0,
        0,
        0.0
      )

    assert polygon.dom_id === "live-map-polygon-district"

    assert polygon.points_attribute ===
             "128.0,128.0 135.11,128.0 135.11,120.85"

    assert polygon.type === :polygon
  end

  defp ring(points), do: Enum.map(points, fn {lat, lng} -> %{latitude: lat, longitude: lng} end)

  test "projects the holes of a polygon, in the copy of the world of its points" do
    polygon =
      Marker.project_shape(
        :polygon,
        %{
          id: "fog",
          group: :fog,
          points: ring([{-10, -10}, {-10, 10}, {10, 10}, {10, -10}]),
          holes: [
            ring([{-5, -5}, {-5, 5}, {5, 5}]),
            # The same hole, in the copy of the world on the right.
            ring([{-5, 355}, {-5, 365}, {5, 365}]),
            # A hole of less than half a pixel has no area.
            ring([{0, 0}, {0, 0.001}, {0.001, 0.001}])
          ]
        },
        "live-map",
        0,
        0,
        0,
        0,
        0.0
      )

    assert polygon.group === "fog"
    assert [hole, hole] = polygon.holes
    assert hole === [{124.44, 131.56}, {131.56, 131.56}, {131.56, 124.44}]

    assert polygon.path ===
             "M120.89,135.15 135.11,135.15 135.11,120.85 120.89,120.85Z " <>
               "M124.44,131.56 131.56,131.56 131.56,124.44Z " <>
               "M124.44,131.56 131.56,131.56 131.56,124.44Z"
  end

  test "a polyline has no holes, and a shape with no group has none" do
    polyline =
      Marker.project_shape(
        :polyline,
        %{points: ring([{0, 0}, {0, 10}]), holes: [ring([{0, 0}, {0, 1}, {1, 1}])]},
        "live-map",
        0,
        0,
        0,
        0,
        0.0
      )

    assert polyline.holes === []
    assert polyline.group === nil
  end

  test "a shape with no points, and a line over the line of 180° to the west" do
    empty =
      Marker.project_shape(
        :polygon,
        %{points: [], holes: [ring([{-5, -5}, {-5, 5}, {5, 5}])]},
        "live-map",
        0,
        0,
        0,
        0,
        0.0
      )

    assert empty.points === []
    assert empty.points_attribute === ""
    assert [[_, _, _]] = empty.holes

    # From -170° to 170°: one step of 20° to the west, not 340° to the east.
    line =
      Marker.project_shape(
        :polyline,
        %{points: ring([{0, -170}, {0, 170}])},
        "live-map",
        0,
        0,
        0,
        0,
        0.0
      )

    assert [{x1, _}, {x2, _}] = line.points
    assert_in_delta x1 - x2, 20 / 360 * 256, 0.1
  end
end
