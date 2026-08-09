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
end
