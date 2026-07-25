defmodule LiveMap.MarkerTest do
  use ExUnit.Case, async: true

  alias LiveMap.Marker

  test "projects slot data into renderable marker overlay data" do
    marker =
      Marker.project(
        %{id: 42, latitude: "0", longitude: "0", label: "Center marker"},
        "live-map",
        0,
        0
      )

    assert marker.id === "42"
    assert marker.dom_id === "live-map-marker-42"
    assert marker.label === "Center marker"
    assert_in_delta marker.x, 0.5, 1.0e-6
    assert_in_delta marker.y, 0.5, 1.0e-6
    assert marker.has_body === false
  end

  test "projects polyline points into SVG point coordinates" do
    polyline =
      Marker.project_shape(
        :polyline,
        %{id: "route", points: [%{latitude: 0, longitude: 0}, %{latitude: 0, longitude: 10}]},
        "live-map",
        0,
        0
      )

    assert polyline.id === "route"
    assert polyline.dom_id === "live-map-polyline-route"
    assert polyline.points === [{0.5, 0.5}, {0.5277777777777778, 0.5}]
    assert polyline.points_attribute === "0.5,0.5 0.5277777777777778,0.5"
    assert polyline.type === :polyline
  end

  test "uses fallback DOM ids and preserves float coordinates" do
    marker =
      Marker.project(
        %{latitude: 1.5, longitude: 2.5, label: "Float marker", inner_block: fn -> nil end},
        "live-map",
        1,
        3
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
        2
      )

    assert marker.id === nil
    assert marker.dom_id === "live-map-marker-3"
    assert marker.has_body === true
    assert marker.latitude === 1.5
    assert marker.longitude === 2.5
    assert polygon.dom_id === "live-map-polygon-2"
  end

  test "raises on invalid marker coordinates" do
    assert_raise ArgumentError, ~r/invalid marker coordinate/, fn ->
      Marker.project(%{latitude: "north", longitude: 0, label: "Bad marker"}, "live-map", 0, 0)
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
        0
      )

    assert polygon.dom_id === "live-map-polygon-district"

    assert polygon.points_attribute ===
             "0.5,0.5 0.5277777777777778,0.5 0.5277777777777778,0.47208011206491635"

    assert polygon.type === :polygon
  end
end
