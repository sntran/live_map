defmodule LiveMap.CoordinateTest do
  use ExUnit.Case, async: true

  alias LiveMap.Coordinate

  test "parses all supported coordinate pair forms" do
    assert Coordinate.parse_pair(" 1.5, -2.25 ", :center) === {1.5, -2.25}
    assert Coordinate.parse_pair({1, 2}, :center) === {1.0, 2.0}
    assert Coordinate.parse_pair([1, 2], :center) === {1.0, 2.0}
    assert Coordinate.parse_pair(%{lat: 1, lng: 2}, :center) === {1.0, 2.0}
    assert Coordinate.parse_pair(%{"lat" => 1, "lng" => 2}, :center) === {1.0, 2.0}
  end

  test "parses individual numeric coordinate values" do
    assert Coordinate.parse_number(1.5, :position) === 1.5
    assert Coordinate.parse_number(2, :position) === 2.0
    assert Coordinate.parse_number(" -3.25 ", :position) === -3.25
  end

  test "rejects malformed coordinate pairs and numbers" do
    assert_raise ArgumentError, ~r/invalid center/, fn ->
      Coordinate.parse_pair("1", :center)
    end

    assert_raise ArgumentError, ~r/invalid center/, fn ->
      Coordinate.parse_pair(%{latitude: 1, longitude: 2}, :center)
    end

    assert_raise ArgumentError, ~r/invalid position coordinate/, fn ->
      Coordinate.parse_number(:north, :position)
    end
  end
end
