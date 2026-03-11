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
end
