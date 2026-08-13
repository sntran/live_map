defmodule LiveMap.VectorTile.Plug do
  @moduledoc """
  A mountable Plug that renders a trusted MVT source as standalone SVG tiles.

  Mount it with `forward/3` and point a LiveMap SVG `tile_source` at the same
  path. Upstream source URLs and headers come only from Plug initialization;
  request data selects tile coordinates and never an arbitrary upstream URL.

  The endpoint negotiates gzip responses by default. Set `compress: false` when
  compression is handled by a reverse proxy or CDN.

  Rendered tiles are not retained in process. Applications can compose this
  Plug behind their preferred cache by initializing it once and calling it
  after a cache miss.
  """

  @behaviour Plug

  import Bitwise, only: [<<<: 2]
  import Plug.Conn

  require Logger

  alias LiveMap.Style
  alias LiveMap.Tile
  alias LiveMap.VectorTile

  @default_max_display_zoom 22
  @default_max_age 86_400

  @impl true
  def init(opts) when is_list(opts) do
    source = opts |> Keyword.fetch!(:source) |> Tile.normalize_source()

    if source.type != :mvt do
      raise ArgumentError, "LiveMap.VectorTile.Plug source must be an MVT tile source"
    end

    base_style = Keyword.get(opts, :base_style, "colorful")
    styles = Keyword.get(opts, :styles, [])
    custom_css = Style.to_css(styles, base_style)
    max_display_zoom = non_negative_option!(opts, :max_display_zoom, @default_max_display_zoom)
    max_age = non_negative_option!(opts, :max_age, @default_max_age)
    compress = boolean_option!(opts, :compress, true)

    profile =
      :crypto.hash(:sha256, :erlang.term_to_binary({source, base_style, styles}))
      |> Base.encode16(case: :lower)

    %{
      source: source,
      base_style: base_style,
      styles: styles,
      custom_css: custom_css,
      max_display_zoom: max_display_zoom,
      max_age: max_age,
      compress: compress,
      profile: profile
    }
  end

  @impl true
  def call(%Plug.Conn{method: method} = conn, config) when method in ["GET", "HEAD"] do
    case parse_tile(conn.path_info, config.max_display_zoom) do
      {:ok, {zoom, x, y}} -> serve_tile(conn, config, zoom, x, y)
      :error -> send_error(conn, 404, "vector tile not found")
    end
  end

  def call(conn, _config) do
    conn
    |> put_resp_header("allow", "GET, HEAD")
    |> send_error(405, "method not allowed")
  end

  defp serve_tile(conn, config, zoom, x, y) do
    result =
      case VectorTile.render(config.source, zoom, x, y,
             custom_css: config.custom_css,
             id_prefix: "live-map-vector-tile-#{config.profile}-#{zoom}-#{x}-#{y}"
           ) do
        {:ok, body} ->
          etag = ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}")
          {:ok, response(body, etag, config.compress)}

        {:error, reason} ->
          {:error, reason}
      end

    case result do
      {:ok, response} -> send_svg(conn, config, response)
      {:error, reason} -> log_and_send_failure(conn, zoom, x, y, reason)
    end
  end

  defp send_svg(conn, config, response) do
    {body, etag, content_encoding} = select_representation(conn, response)

    conn =
      conn
      |> put_resp_content_type("image/svg+xml", "utf-8")
      |> put_resp_header("cache-control", "public, max-age=#{config.max_age}")
      |> put_resp_header("vary", "accept-encoding")
      |> put_resp_header("etag", etag)
      |> maybe_put_content_encoding(content_encoding)

    if etag_matches?(conn, etag) do
      send_resp(conn, 304, "")
    else
      send_resp(conn, 200, if(conn.method == "HEAD", do: "", else: body))
    end
  end

  defp response(body, etag, false), do: %{body: body, etag: etag}

  defp response(body, etag, true) do
    gzip_body = :zlib.gzip(body)

    if byte_size(gzip_body) < byte_size(body) do
      gzip_etag = ~s("#{Base.encode16(:crypto.hash(:sha256, gzip_body), case: :lower)}")
      %{body: body, etag: etag, gzip_body: gzip_body, gzip_etag: gzip_etag}
    else
      %{body: body, etag: etag}
    end
  end

  defp select_representation(
         conn,
         %{body: body, etag: etag, gzip_body: gzip_body, gzip_etag: gzip_etag}
       ) do
    if accepts_gzip?(conn), do: {gzip_body, gzip_etag, "gzip"}, else: {body, etag, nil}
  end

  defp select_representation(_conn, %{body: body, etag: etag}), do: {body, etag, nil}

  defp maybe_put_content_encoding(conn, nil), do: conn

  defp maybe_put_content_encoding(conn, encoding) do
    put_resp_header(conn, "content-encoding", encoding)
  end

  defp accepts_gzip?(conn) do
    conn
    |> get_req_header("accept-encoding")
    |> Enum.flat_map(&String.split(&1, ","))
    |> accepted_encoding_quality("gzip")
    |> Kernel.>(0.0)
  end

  defp accepted_encoding_quality(values, encoding) do
    parsed = Enum.map(values, &parse_encoding/1)

    case Enum.filter(parsed, fn {name, _quality} -> name == encoding end) do
      [] -> wildcard_quality(parsed)
      explicit -> explicit |> Enum.map(&elem(&1, 1)) |> Enum.max()
    end
  end

  defp wildcard_quality(parsed) do
    parsed
    |> Enum.filter(fn {name, _quality} -> name == "*" end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.max(fn -> 0.0 end)
  end

  defp parse_encoding(value) do
    [name | parameters] = value |> String.downcase() |> String.split(";")

    quality =
      Enum.find_value(parameters, 1.0, fn parameter ->
        case String.split(parameter, "=", parts: 2) do
          [key, quality] ->
            if String.trim(key) == "q", do: parse_quality(quality)

          _other ->
            nil
        end
      end)

    {String.trim(name), quality}
  end

  defp parse_quality(value) do
    case value |> String.trim() |> Float.parse() do
      {quality, ""} when quality >= 0.0 and quality <= 1.0 -> quality
      _invalid -> 0.0
    end
  end

  defp etag_matches?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.any?(fn candidate ->
      candidate = candidate |> String.trim() |> String.trim_leading("W/")
      candidate in [etag, "*"]
    end)
  end

  defp log_and_send_failure(conn, zoom, x, y, reason) do
    Logger.error("LiveMap.VectorTile.Plug failed to render #{zoom}/#{x}/#{y}: #{inspect(reason)}")

    send_error(conn, 502, "failed to render vector tile")
  end

  defp send_error(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, if(conn.method == "HEAD", do: "", else: message))
  end

  defp parse_tile([zoom, x, y_svg], max_display_zoom) do
    with {zoom, ""} <- Integer.parse(zoom),
         {x, ""} <- Integer.parse(x),
         {y, ""} <- parse_svg_y(y_svg),
         true <- zoom >= 0 and zoom <= max_display_zoom,
         limit = 1 <<< zoom,
         true <- x >= 0 and x < limit and y >= 0 and y < limit do
      {:ok, {zoom, x, y}}
    else
      _invalid -> :error
    end
  end

  defp parse_tile(_path_info, _max_display_zoom), do: :error

  defp parse_svg_y(value) do
    suffix_size = byte_size(".svg")

    if byte_size(value) > suffix_size and String.ends_with?(value, ".svg") do
      value
      |> binary_part(0, byte_size(value) - suffix_size)
      |> Integer.parse()
    else
      :error
    end
  end

  defp non_negative_option!(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value >= 0 ->
        value

      value ->
        raise ArgumentError, "#{key} must be a non-negative integer, got: #{inspect(value)}"
    end
  end

  defp boolean_option!(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_boolean(value) -> value
      value -> raise ArgumentError, "#{key} must be a boolean, got: #{inspect(value)}"
    end
  end
end
