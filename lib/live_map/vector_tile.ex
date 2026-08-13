defmodule LiveMap.VectorTile do
  @moduledoc """
  Renders a configured MVT source tile as a standalone SVG image.
  """

  import Bitwise, only: [<<<: 2]

  alias LiveMap.MVT
  alias LiveMap.Style
  alias LiveMap.Tile

  @type coordinate :: non_neg_integer()

  @doc """
  Fetches and renders the display tile at `zoom/x/y`.

  The source's `max_zoom` is respected by fetching and cropping the appropriate
  ancestor while still applying label and style rules for the display zoom.
  """
  @spec render(Tile.source(), non_neg_integer(), coordinate(), coordinate(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def render(source, zoom, x, y, opts \\ [])
      when is_integer(zoom) and zoom >= 0 and is_integer(x) and x >= 0 and is_integer(y) and
             y >= 0 do
    source = Tile.normalize_source(source)

    if source.type != :mvt do
      raise ArgumentError, "LiveMap.VectorTile.render/5 requires an MVT tile source"
    end

    custom_css =
      Keyword.get_lazy(opts, :custom_css, fn ->
        Style.to_css(Keyword.get(opts, :styles, []), Keyword.get(opts, :base_style, "colorful"))
      end)

    source_zoom = min(zoom, source.max_zoom || zoom)
    overzoom_scale = 1 <<< (zoom - source_zoom)

    source_tile = %{
      z: source_zoom,
      x: div(x, overzoom_scale),
      y: div(y, overzoom_scale)
    }

    id_prefix =
      Keyword.get_lazy(opts, :id_prefix, fn ->
        hash =
          :crypto.hash(:sha256, :erlang.term_to_binary({source, zoom, x, y, custom_css}))
          |> Base.encode16(case: :lower)
          |> binary_part(0, 16)

        "live-map-vector-tile-#{hash}"
      end)

    with {:ok, body} <- Tile.fetch_vector_tile(source, source_tile),
         {:ok, svg} <- MVT.decode(body, id_prefix: id_prefix, custom_css: custom_css, zoom: zoom) do
      svg = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
      {:ok, put_overzoom_view_box(svg, x, y, overzoom_scale)}
    end
  end

  defp put_overzoom_view_box(svg, _x, _y, 1), do: svg

  defp put_overzoom_view_box(svg, x, y, scale) do
    size = 1 / scale

    view_box =
      Enum.map_join([rem(x, scale) * size, rem(y, scale) * size, size, size], " ", fn number ->
        number
        |> :erlang.float_to_binary(decimals: 12)
        |> String.trim_trailing("0")
        |> String.trim_trailing(".")
      end)

    String.replace(svg, ~s(viewBox="0 0 1 1"), ~s(viewBox="#{view_box}"), global: false)
  end
end
