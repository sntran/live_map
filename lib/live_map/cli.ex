defmodule LiveMap.CLI do
  @moduledoc """
  Command Line Interface for generating a map with LiveMap.

  Usage:
      ./live_map --latitude 10.4197639 --longitude 107.1070841 --zoom 11 --width 640 --height 360 > map.svg
      ./live_map -y 10.4197639 -x 107.1070841 -z 11 -w 640 -h 360 > map.svg
  """

  @defaults %{
    id: "live-map",
    latitude: 0.0,
    longitude: 0.0,
    zoom: 0,
    width: 300,
    height: 150,
    title: "",
    style: [],
    # @FIXME: Find a way NOT to render these controls.
    zoom_in: [],
    zoom_out: [],
    myself: "",
  }

  def main(args) do
    options = [
      strict: [
        latitude: :float,
        longitude: :float,
        zoom: :integer,
        width: :integer,
        height: :integer,
      ],
      aliases: [
        x: :longitude,
        y: :latitude,
        z: :zoom,
        w: :width,
        h: :height,
      ]
    ]

    {opts, _, _} = OptionParser.parse(args, options)
    assigns = Enum.into(opts, @defaults)
    tiles = LiveMap.tiles(assigns)

    assigns
    |> Map.put(:tiles, tiles)
    |> LiveMap.render()
    |> Phoenix.HTML.Safe.to_iodata
    |> IO.puts
  end
end
