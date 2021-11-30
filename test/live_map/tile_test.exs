defmodule LiveMap.TileTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  use Bitwise, only_operators: true

  alias LiveMap.Tile
  doctest Tile

  property "conversion between x and longitude" do
    check all zoom <- StreamData.integer(0..18),
      x <- StreamData.integer(0..(1 <<< zoom) - 1),
      longitude = Tile.longitude(x, zoom) do

      assert round(Tile.x(longitude, zoom)) === x
    end
  end

  property "conversion between y and latitude" do
    check all zoom <- StreamData.integer(0..18),
      y <- StreamData.integer(0..(1 <<< zoom) - 1),
      latitude = Tile.latitude(y, zoom) do

      assert round(Tile.y(latitude, zoom)) === y
    end
  end
end
