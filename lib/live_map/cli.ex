defmodule LiveMap.CLI do
  @moduledoc """
  Command Line Interface for generating a map with LiveMap.

  Usage:
      ./live_map --latitude 10.4197639 --longitude 107.1070841 --zoom 11 --width 640 --height 360 > map.svg
      ./live_map -y 10.4197639 -x 107.1070841 -z 11 -w 640 -h 360 > map.svg
      ./live_map --tile-url https://vector.openstreetmap.org/shortbread_v1/{zoom}/{x}/{y}.mvt --tile-user-agent "MyApp/1.0 (contact@example.com)" > map.svg
  """

  alias LiveMap.Tile

  @default_mvt_url "https://vector.openstreetmap.org/$VERSION/{zoom}/{x}/{y}.mvt"
  @default_mvt_version "shortbread_v1"

  @defaults %{
    id: "live-map",
    latitude: 0.0,
    longitude: 0.0,
    zoom: 0,
    width: 300,
    height: 150,
    title: "",
    style: [],
    myself: nil
  }

  def main(args) do
    options = [
      strict: [
        latitude: :float,
        longitude: :float,
        zoom: :integer,
        width: :integer,
        height: :integer,
        tile_url: :string,
        tile_format: :string,
        tile_version: :string,
        tile_user_agent: :string
      ],
      aliases: [
        x: :longitude,
        y: :latitude,
        z: :zoom,
        w: :width,
        h: :height
      ]
    ]

    {opts, _, _} = OptionParser.parse(args, options)

    assigns =
      opts
      |> Keyword.drop([:tile_url, :tile_format, :tile_version, :tile_user_agent])
      |> Enum.into(@defaults)
      |> Map.put(:tile_source, build_tile_source(opts))

    assigns
    |> LiveMap.render()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.puts()
  end

  defp build_tile_source(opts) do
    tile_format = normalize_tile_format(opts[:tile_format])
    url = tile_url(opts[:tile_url], tile_format)
    headers = build_headers(opts[:tile_user_agent])

    %{}
    |> Map.put(:url, url)
    |> Map.put(:headers, headers)
    |> maybe_put(:type, tile_format)
    |> maybe_put(:version, tile_version(opts, tile_format, url))
  end

  defp build_headers(nil), do: []
  defp build_headers(user_agent), do: [{"user-agent", user_agent}]

  defp tile_url(nil, :mvt), do: @default_mvt_url
  defp tile_url(nil, _tile_format), do: Tile.default_source().url
  defp tile_url(url, _tile_format), do: url

  defp tile_version(opts, :mvt, @default_mvt_url), do: opts[:tile_version] || @default_mvt_version
  defp tile_version(opts, _tile_format, _url), do: opts[:tile_version]

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_tile_format(nil), do: nil
  defp normalize_tile_format("raster"), do: :raster
  defp normalize_tile_format("mvt"), do: :mvt
  defp normalize_tile_format(format) when format in [:raster, :mvt], do: format

  defp normalize_tile_format(format) do
    raise ArgumentError, "unsupported tile format: #{inspect(format)}"
  end
end
