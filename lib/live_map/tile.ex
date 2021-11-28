defmodule LiveMap.Tile do
  @moduledoc """
  This module contains functions to manipulate map tiles.
  """
  alias :math, as: Math
  alias __MODULE__, as: Tile
  require Logger

  @type latitude :: number()
  @type longitude :: number()
  @type zoom :: pos_integer()
  @type x :: pos_integer()
  @type y :: pos_integer()

  defstruct [:latitude, :longitude, :raw_x, :raw_y, :x, :y, :z]
  @type t :: %__MODULE__{
    latitude: latitude(),
    longitude: longitude(),
    raw_x: number(),
    raw_y: number(),
    x: x(),
    y: y(),
    z: zoom()
  }

  # Use Bitwise operations for performant 2^z calculation.
  use Bitwise, only_operators: true
  # Precalculates at compile time to avoid calling :math.pi
  # and performing a division at runtime.
  @pi Math.pi()
  @deg_to_rad @pi / 180.0
  @tile_size 256

  @doc """
  Retrieves a tile at certain coordinates and zoom level.

  Based on https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames.

  Examples:

      iex> tile = LiveMap.Tile.at(0, 0, 0)
      iex> tile.x
      0
      iex> tile.y
      0

      iex> tile = LiveMap.Tile.at(360, 170.1022, 0)
      iex> tile.x
      0
      iex> tile.y
      0

      iex> tile = LiveMap.Tile.at(47.47607, 7.56198, 16)
      iex> tile.x
      34144
      iex> tile.y
      22923

  """
  @spec at(latitude(), longitude(), zoom()) :: t()
  def at(latitude, longitude, zoom) when is_integer(zoom) do
    x = Tile.x(longitude, zoom)
    y = Tile.y(latitude, zoom)

    %Tile{
      latitude: latitude,
      longitude: longitude,
      raw_x: x,
      raw_y: y,
      x: floor(x),
      y: floor(y),
      z: zoom,
    }
  end

  @doc """
  Converts a longitude at certain zoom to tile x number

  Notes that the return value is not rounded. If used with slippy map,
  round it down to the nearest integer.

  Examples:

      iex> floor(Tile.x(0, 0))
      0

      iex> floor(Tile.x(170.1022, 0))
      0

      iex> floor(Tile.x(7.56198, 16))
      34144

  """
  @spec x(longitude(), zoom()) :: number()
  def x(longitude, zoom) do
    (1 <<< zoom) * ((longitude + 180) / 360)
  end

  @doc """
  Convers a latitude at certain zoom to tile y number

  Notes that the return value is not rounded. If used with slippy map,
  round it down to the nearest integer.

  Examples:

      iex> floor(Tile.y(0, 0))
      0

      iex> floor(Tile.y(360, 0))
      0

      iex> floor(Tile.y(47.47607, 16))
      22923

  """
  @spec y(latitude(), zoom()) :: number()
  def y(latitude, zoom) do
    radian = latitude * @deg_to_rad
    r = Math.log(Math.tan(radian) + 1 / Math.cos(radian)) / @pi
    (1 <<< zoom) * (1 - r) / 2
  end

  @doc """
  Maps tiles around a center tile that covers a rectangle box.

  Note that by default, the resulting tiles do not have latitude and longitude
  coordinates. If such values are desired, use the last parameter to provide
  a custom mapper function to also load the coordinates.

  Examples:

      # At zoom 0, the whole world is rendered in 1 tile.
      iex> center = LiveMap.Tile.at(0, 0, 0)
      iex> [center] == LiveMap.Tile.map(center, 256, 256)
      true

      # At zoom 1, 4 tiles are used on a 512x512 map.
      iex> center = LiveMap.Tile.at(0, 0, 1)
      iex> tiles = LiveMap.Tile.map(center, 512, 512)
      iex> Enum.map(tiles, fn %{x: x, y: y} -> {x, y} end)
      [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

      # Can also pass a mapper function to transform the tiles.
      iex> center = LiveMap.Tile.at(0, 0, 1)
      iex> LiveMap.Tile.map(center, 512, 512, fn %{x: x, y: y} -> {x, y} end)
      [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

  """
  @spec map(t(), number(), number(), function()) :: list()
  def map(center, width, height, mapper \\ &Function.identity/1)
  # Special case for zoom level 0, in which the whole world is on 1 tile.
  def map(%Tile{z: 0} = center, _width, _height, mapper), do: [mapper.(center)]
  def map(%Tile{raw_x: center_x, raw_y: center_y, z: zoom}, width, height, mapper) when zoom >= 0 do
    half_width = (0.5 * width) / @tile_size
    half_height = (0.5 * height) / @tile_size
    max_tile = 1 <<< zoom

    x_min = floor(center_x - half_width)
    y_min = floor(center_y - half_height)
    x_max = ceil(center_x + half_width)
    y_max = ceil(center_y + half_height)

    for x <- x_min..x_max - 1,
      y <- y_min..y_max - 1,
      # x and y may have crossed the date line
      tile_x = rem(x + max_tile, max_tile),
      tile_y = rem(y + max_tile, max_tile) do
      mapper.(%Tile{
        raw_x: tile_x,
        raw_y: tile_y,
        x: tile_x,
        y: tile_y,
        z: zoom,
      })
    end
  end

  @doc """
  Maps tiles around a center coordinates and zoom that covers a rectangle box.

  The coordinates and zoom are used to generate a `Tile` and pass to `map/4`.

  Examples:

      iex> [center] = LiveMap.Tile.map(0, 0, 0, 256, 256)
      iex> center.x
      0
      iex> center.y
      0

  """
  @spec map(latitude(), longitude(), zoom(), number(), number(), function()) :: list()
  def map(latitude, longitude, zoom, width, height, mapper \\ &Function.identity/1) do
    center = Tile.at(latitude, longitude, zoom)
    Tile.map(center, width, height, mapper)
  end
end
