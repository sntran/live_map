defmodule LiveMap.Tile do
  @moduledoc """
  This module contains functions to manipulate map tiles.
  """

  require Logger

  alias :math, as: Math
  alias __MODULE__, as: Tile
  alias LiveMap.MVT

  @type latitude :: number()
  @type longitude :: number()
  @type zoom :: non_neg_integer()
  @type x :: non_neg_integer()
  @type y :: non_neg_integer()
  @type source_type :: :raster | :mvt
  @type source :: %{
          required(:type) => source_type(),
          required(:url) => String.t(),
          required(:headers) => [{String.t(), String.t()}],
          optional(:version) => String.t() | nil,
          optional(:max_zoom) => non_neg_integer() | nil
        }
  @type prepared_tile_layer :: %{
          required(:source) => source(),
          required(:defs) => list(),
          required(:tiles) => list(map())
        }

  @enforce_keys [:x, :y, :z]
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
  import Bitwise, only: [<<<: 2]
  # Precalculates at compile time to avoid calling :math.pi
  # and performing a division at runtime.
  @pi Math.pi()
  @deg_to_rad @pi / 180.0
  @rad_to_deg 180.0 / @pi
  @tile_size 256
  @default_source %{
    type: :raster,
    url: "https://tile.openstreetmap.org/{zoom}/{x}/{y}.png",
    version: nil,
    max_zoom: nil,
    headers: []
  }
  @default_mvt_max_zoom 14
  @default_user_agent "LiveMap/#{Application.spec(:live_map, :vsn) || "dev"}"
  @req_module :"Elixir.Req"

  @doc """
  Returns the default raster tile source.

  Examples:

      iex> LiveMap.Tile.default_source().type
      :raster

  """
  @spec default_source() :: source()
  def default_source, do: @default_source

  @doc """
  Retrieves a tile at certain coordinates and zoom level.

  Based on https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames.

  Examples:

      iex> tile = LiveMap.Tile.at(0, 0, 0)
      iex> Kernel.match?(%Tile{x: 0, y: 0}, tile)
      true

      iex> tile = LiveMap.Tile.at(360, 170.1022, 0)
      iex> Kernel.match?(%Tile{x: 0, y: 0}, tile)
      true

      iex> tile = LiveMap.Tile.at(47.47607, 7.56198, 16)
      iex> Kernel.match?(%Tile{x: 34144, y: 22923}, tile)
      true

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
      z: zoom
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
  Converts a latitude at certain zoom to tile y number

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
  Converts a tile x number to longitude at certain zoom level.

  Examples:

      iex> Tile.longitude(0, 0)
      -180.0

      iex> Tile.longitude(34144, 16)
      7.55859375
  """
  @spec longitude(x(), zoom()) :: longitude()
  def longitude(x, zoom) do
    x / (1 <<< zoom) * 360 - 180
  end

  @doc """
  Converts a tile y number to latitude at certain zoom level.

  Examples:

      iex> Tile.latitude(0, 0)
      85.0511287798066

      iex> Tile.latitude(22923, 16)
      47.47637579720934
  """
  @spec latitude(y(), zoom()) :: latitude()
  def latitude(y, zoom) do
    Math.atan(Math.sinh(@pi * (1 - 2 * y / (1 <<< zoom)))) * @rad_to_deg
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


  def map(%Tile{raw_x: center_x, raw_y: center_y, z: zoom}, width, height, mapper)
      when zoom >= 0 do
    half_width = 0.5 * abs(width) / @tile_size
    half_height = 0.5 * abs(height) / @tile_size

    x_min = floor(center_x - half_width)
    y_min = floor(center_y - half_height)
    x_max = ceil(center_x + half_width)
    y_max = ceil(center_y + half_height)

    if x_max <= x_min or y_max <= y_min do
      []
    else
      n = 1 <<< zoom

      for x <- x_min..(x_max - 1),
          y <- y_min..(y_max - 1),
          y >= 0,
          y < n do
        mapper.(%Tile{
          raw_x: x,
          raw_y: y,
          x: x,
          y: y,
          z: zoom
        })
      end
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

  @doc """
  Normalizes a tile source and prepares renderable tile layer data.

  Raster sources are expanded into `<image>` tile entries. Vector sources are
  fetched with Req, decoded through `LiveMap.MVT`, and returned as shared SVG
  definitions plus per-tile `<use>` entries.

  Examples:

      iex> layer = LiveMap.Tile.prepare_layer([%{x: 0, y: 0, z: 0}], %{url: "https://tiles.example.com/{z}/{x}/{y}.png"})
      iex> layer.source.type
      :raster
      iex> hd(layer.tiles).href
      "https://tiles.example.com/0/0/0.png"

  """
  @spec prepare_layer(list(map()), map() | nil) :: prepared_tile_layer()
  def prepare_layer(tiles, source, custom_css \\ "") when is_list(tiles) do
    source = normalize_source(source)

    case source.type do
      :raster ->
        %{
          source: source,
          defs: [],
          tiles: Enum.map(tiles, &prepare_raster_tile(&1, source))
        }

      :mvt ->
        ensure_req!()

        vector_layer = prepare_vector_layer(tiles, source, custom_css)
        Map.put(vector_layer, :source, source)
    end
  end

  defp prepare_vector_layer([], _source, _custom_css), do: %{defs: [], tiles: []}

  defp prepare_vector_layer(tiles, source, custom_css) do
    requests = build_vector_requests(tiles, source, custom_css)
    results = fetch_vector_results(requests)

    defs =
      requests
      |> Map.values()
      |> Enum.flat_map(fn request ->
        case Map.get(results, request.key, {:error, sanitize_error(:fetch, :task_exit)}) do
          {:ok, svg_binary} ->
            [
              Phoenix.HTML.raw(
                inject_definition_id(svg_binary, request.def_id, request.source_tile)
              )
            ]

          {:error, _error} ->
            []
        end
      end)

    prepared_tiles =
      requests
      |> Map.values()
      |> Enum.flat_map(fn request ->
        case Map.get(results, request.key, {:error, sanitize_error(:fetch, :task_exit)}) do
          {:ok, _svg_binary} ->
            Enum.map(request.display_tiles, &prepare_vector_tile(&1, request))

          {:error, error_meta} ->
            Enum.map(request.display_tiles, &prepare_error_tile(&1, error_meta))
        end
      end)

    %{defs: defs, tiles: prepared_tiles}
  end

  defp prepare_raster_tile(tile, source) do
    n = 1 <<< tile.z
    fetch_x = rem(rem(tile.x, n) + n, n)
    fetch_y = tile.y

    %{
      type: :image,
      x: tile.x * 256,
      y: tile.y * 256,
      width: 256,
      height: 256,
      href: expand_url(source, %{tile | x: fetch_x, y: fetch_y})
    }
  end

  defp build_vector_requests(tiles, source, custom_css) do
    Enum.reduce(tiles, %{}, fn tile, requests ->
      request = vector_request(tile, source, custom_css)

      Map.update(requests, request.key, request, fn existing ->
        %{existing | display_tiles: existing.display_tiles ++ [request.display_tile]}
      end)
    end)
  end

  defp vector_request(tile, source, custom_css) do
    source_zoom = min(tile.z, source.max_zoom || tile.z)
    overzoom_levels = tile.z - source_zoom
    overzoom_scale = 1 <<< overzoom_levels

    n = 1 <<< tile.z
    fetch_x = rem(rem(tile.x, n) + n, n)
    fetch_y = tile.y

    source_tile = %{
      x: div(fetch_x, overzoom_scale),
      y: div(fetch_y, overzoom_scale),
      z: source_zoom
    }

    source_url = expand_url(source, source_tile)
    source_key = {source_zoom, source_tile.x, source_tile.y, Enum.sort(source.headers)}

    def_id =
      "live-map-vector-source-#{source_zoom}-#{source_tile.x}-#{source_tile.y}-#{short_hash(source_url)}"

    display_tile = %{
      x: tile.x * 256,
      y: tile.y * 256,
      width: 256,
      height: 256,
      source_tile: source_tile,
      view_box: child_view_box(fetch_x, fetch_y, overzoom_scale)
    }

    %{
      key: source_key,
      url: source_url,
      headers: source.headers,
      def_id: def_id,
      source_tile: source_tile,
      display_tile: display_tile,
      display_tiles: [display_tile],
      custom_css: custom_css
    }
  end

  defp fetch_vector_results(requests) do
    requests
    |> Map.values()
    |> Task.async_stream(&fetch_vector_request/1,
      max_concurrency: max(1, System.schedulers_online()),
      timeout: 30_000,
      ordered: false
    )
    |> Enum.reduce(%{}, fn
      {:ok, {key, result}}, acc ->
        Map.put(acc, key, result)

      {:exit, reason}, acc ->
        Map.put(acc, {:task_exit, map_size(acc)}, {:error, sanitize_error(:fetch, reason)})
    end)
  end

  defp fetch_vector_request(request) do
    result =
      case fetch_vector_body(request.url, request.headers) do
      {:ok, body} ->
          case MVT.decode(body, id_prefix: request.def_id, custom_css: request.custom_css) do
            {:ok, svg} ->
              {:ok, svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()}

            {:error, reason} ->
              Logger.error(
                "LiveMap failed to decode vector tile #{request.url}: #{inspect(reason)}"
              )

              {:error, sanitize_error(:decode, reason)}
          end

        {:error, reason} ->
          Logger.error("LiveMap failed to fetch vector tile #{request.url}: #{inspect(reason)}")
          {:error, sanitize_error(:fetch, reason)}
      end

    {request.key, result}
  end

  defp fetch_vector_body(url, headers) do
    options = [
      headers: merge_default_headers(headers),
      cache: true,
      compressed: true,
      raw: true,
      decode_body: false,
      http_errors: :return,
      retry: false
    ]

    case apply(@req_module, :get, [url, options]) do
      {:ok, %{status: status} = response} when status >= 200 and status < 300 ->
        {:ok, normalize_response_body(Map.get(response, :body, ""))}

      {:ok, %{status: status}} when is_integer(status) ->
        {:error, {:http_status, status}}

      {:error, exception} ->
        {:error, normalize_req_error(exception)}
    end
  end

  defp prepare_vector_tile(display_tile, request) do
    %{
      type: :svg_use,
      def_id: request.def_id,
      x: display_tile.x,
      y: display_tile.y,
      width: display_tile.width,
      height: display_tile.height,
      view_box: display_tile.view_box,
      state: "ready",
      source_tile: format_source_tile(display_tile.source_tile)
    }
  end

  defp prepare_error_tile(display_tile, error_meta) do
    %{
      type: :error,
      x: display_tile.x,
      y: display_tile.y,
      width: display_tile.width,
      height: display_tile.height,
      state: "error",
      error_kind: error_meta.kind,
      error_reason: error_meta.reason,
      source_tile: format_source_tile(display_tile.source_tile)
    }
  end

  defp normalize_source(nil), do: @default_source

  defp normalize_source(source) when is_map(source) do
    url = source[:url] || source["url"] || raise ArgumentError, "source.url is required"
    normalized_url = normalize_url(url)
    type = source[:type] || source["type"] || infer_source_type(normalized_url)
    version = source[:version] || source["version"]
    max_zoom = source[:max_zoom] || source["max_zoom"]
    headers = normalize_headers(source[:headers] || source["headers"] || [])
    normalized_type = normalize_type(type)

    normalized_source = %{
      type: normalized_type,
      url: normalized_url,
      version: normalize_version(version),
      max_zoom: normalize_max_zoom(max_zoom, normalized_type),
      headers: headers
    }

    validate_source!(normalized_source)
  end

  defp expand_url(source, tile) do
    url =
      source.url
      |> String.replace("{zoom}", Integer.to_string(tile.z))
      |> String.replace("{z}", Integer.to_string(tile.z))
      |> String.replace("{x}", Integer.to_string(tile.x))
      |> String.replace("{y}", Integer.to_string(tile.y))

    case source.version do
      nil ->
        if version_placeholder?(url) do
          raise ArgumentError,
                "source.version is required when the URL contains version placeholders"
        end

        url

      version ->
        url
        |> String.replace("{version}", version)
        |> String.replace("$VERSION", version)
    end
  end

  defp normalize_type(type) when type in [:raster, :mvt], do: type
  defp normalize_type("raster"), do: :raster
  defp normalize_type("mvt"), do: :mvt
  defp normalize_type(type), do: raise(ArgumentError, "unsupported source type: #{inspect(type)}")

  defp infer_source_type(url) do
    if Regex.match?(~r/(?:\.mvt|\.pbf)(?:$|[?#])/i, url) do
      :mvt
    else
      :raster
    end
  end

  defp normalize_url(url) when is_binary(url) and url != "", do: url

  defp normalize_url(url),
    do: raise(ArgumentError, "source.url must be a non-empty string, got: #{inspect(url)}")

  defp normalize_version(nil), do: nil
  defp normalize_version(version) when is_binary(version) and version != "", do: version

  defp normalize_version(version) do
    raise ArgumentError, "source.version must be a non-empty string, got: #{inspect(version)}"
  end

  defp normalize_max_zoom(nil, :mvt), do: @default_mvt_max_zoom
  defp normalize_max_zoom(nil, _type), do: nil

  defp normalize_max_zoom(max_zoom, _type) when is_integer(max_zoom) and max_zoom >= 0,
    do: max_zoom

  defp normalize_max_zoom(max_zoom, _type) do
    raise ArgumentError,
          "source.max_zoom must be a non-negative integer, got: #{inspect(max_zoom)}"
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      {name, value} when is_binary(name) and is_binary(value) -> {name, value}
      %{name: name, value: value} when is_binary(name) and is_binary(value) -> {name, value}
      header -> raise ArgumentError, "invalid tile source header: #{inspect(header)}"
    end)
  end

  defp normalize_headers(headers) do
    raise ArgumentError, "source.headers must be a list, got: #{inspect(headers)}"
  end

  defp validate_source!(%{url: url} = source) do
    uri = URI.parse(url)

    unless uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      raise ArgumentError, "source.url must be an absolute http(s) URL, got: #{inspect(url)}"
    end

    unless Regex.match?(~r/\{zoom\}|\{z\}/, url) do
      raise ArgumentError, "source.url must include a zoom placeholder"
    end

    unless Regex.match?(~r/\{x\}/, url) do
      raise ArgumentError, "source.url must include an x placeholder"
    end

    unless Regex.match?(~r/\{y\}/, url) do
      raise ArgumentError, "source.url must include a y placeholder"
    end

    if is_nil(source.version) and version_placeholder?(url) do
      raise ArgumentError, "source.version is required when the URL contains version placeholders"
    end

    source
  end

  defp version_placeholder?(url), do: Regex.match?(~r/\{version\}|\$VERSION/, url)

  defp merge_default_headers(headers) do
    if Enum.any?(headers, fn {name, _value} -> String.downcase(name) == "user-agent" end) do
      headers
    else
      [
        {"user-agent", Application.get_env(:live_map, :tile_user_agent, @default_user_agent)}
        | headers
      ]
    end
  end

  defp normalize_response_body(body) when is_binary(body), do: body
  defp normalize_response_body(body) when is_list(body), do: IO.iodata_to_binary(body)

  defp normalize_response_body(body),
    do: raise(ArgumentError, "unexpected vector tile response body: #{inspect(body)}")

  defp normalize_req_error(%{reason: reason}) when is_atom(reason), do: reason
  defp normalize_req_error(exception), do: Exception.message(exception)

  defp ensure_req! do
    case Code.ensure_loaded(@req_module) do
      {:module, _module} ->
        case Application.ensure_all_started(:req) do
          {:ok, _apps} -> :ok
          {:error, reason} -> raise RuntimeError, missing_req_message(reason)
        end

      {:error, _reason} ->
        raise RuntimeError, missing_req_message(:not_loaded)
    end
  end

  defp missing_req_message(reason) do
    """
    Vector tile sources require the optional Req dependency at runtime.

    Add {:req, "~> 0.6.2"} to your application's dependencies, or switch the source to a raster URL.
    Req startup failure: #{inspect(reason)}
    """
  end

  defp child_view_box(fetch_x, fetch_y, overzoom_scale) do
    offset_x = rem(fetch_x, overzoom_scale)
    offset_y = rem(fetch_y, overzoom_scale)
    scale = 1 / overzoom_scale

    [
      format_number(offset_x * scale),
      " ",
      format_number(offset_y * scale),
      " ",
      format_number(scale),
      " ",
      format_number(scale)
    ]
  end

  defp inject_definition_id(svg_binary, def_id, source_tile) do
    replacement =
      ~s(<svg id="#{def_id}" data-live-map-source-tile="#{format_source_tile(source_tile)}" )

    String.replace_prefix(svg_binary, "<svg ", replacement)
  end

  defp sanitize_error(kind, {:http_status, status}) do
    %{kind: Atom.to_string(kind), reason: "http-status-#{status}"}
  end

  defp sanitize_error(kind, reason) when is_atom(reason) do
    %{kind: Atom.to_string(kind), reason: reason |> Atom.to_string() |> sanitize_token()}
  end

  defp sanitize_error(kind, reason) do
    %{kind: Atom.to_string(kind), reason: reason |> inspect() |> sanitize_token()}
  end

  defp sanitize_token(token) do
    token
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "unknown"
      value -> value
    end
  end

  defp format_source_tile(%{z: z, x: x, y: y}), do: "#{z}/#{x}/#{y}"

  defp format_number(number) when is_number(number) do
    (number * 1.0)
    |> :erlang.float_to_binary(decimals: 6)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
    |> case do
      "-0" -> "0"
      "" -> "0"
      value -> value
    end
  end

  defp short_hash(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 10)
  end
end
