defmodule LiveMap.PMTiles do
  @moduledoc """
  A reader of the PMTiles archives of version 3: all the tiles of a map in
  one file, as the builds of Protomaps
  (https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md).

  The reader reads only the parts of the file that a tile needs, each with
  a request of a range: the header and the root directory (the first
  16 KiB), a leaf directory, and the data of the tile. It keeps the header,
  the root directory and some leaf directories in an ETS table, so a tile
  near a tile of before needs only the request of its data. The table
  keeps 4 leaf directories by default:

      config :live_map, :pmtiles_leaf_cache, 8

  The URL is an `http` or `https` URL of a server that gives ranges (as R2,
  S3, or the builds of Protomaps), or a `file://` URL of a local file.

  Each request after the first one of a file has `If-Match` with the
  `ETag` of the file. When the file changes at the same URL, the server
  answers `412`: the reader forgets the old file and reads the tile again,
  one time, in the new file. Thus the positions of an old file never read
  the data of a new one.
  """

  import Bitwise

  # The bytes that the specification gives to the header and the root
  # directory.
  @first_bytes 16_384
  # The most levels of leaf directories.
  @max_depth 3
  # The highest zoom level of a tile ID in 64 bits.
  @max_zoom 31
  # The most entries in a directory: a leaf of the planet of Protomaps has
  # about 61,000.
  @max_entries 1_000_000
  # The leaf directories in the cache, by default: about 1.7 MB each for
  # the planet of Protomaps.
  @default_leaf_cache 4
  @table __MODULE__
  @default_user_agent "LiveMap/#{Application.spec(:live_map, :vsn) || "dev"}"
  @req_module :"Elixir.Req"

  @typedoc "The header of an archive."
  @type header :: %{
          root_offset: non_neg_integer(),
          root_length: non_neg_integer(),
          metadata_offset: non_neg_integer(),
          metadata_length: non_neg_integer(),
          leaf_offset: non_neg_integer(),
          leaf_length: non_neg_integer(),
          data_offset: non_neg_integer(),
          data_length: non_neg_integer(),
          internal_compression: non_neg_integer(),
          tile_compression: non_neg_integer(),
          tile_type: non_neg_integer(),
          min_zoom: non_neg_integer(),
          max_zoom: non_neg_integer()
        }

  # A directory, with an entry of each column at the same index: the
  # first tile ID (64 bits), the number of tiles (64 bits, 0 for a leaf
  # directory), the length (32 bits) and the offset (64 bits).
  @typep directory :: %{
           count: non_neg_integer(),
           ids: binary(),
           runs: binary(),
           lengths: binary(),
           offsets: binary()
         }

  @doc """
  The data of the tile `z/x/y` of the archive at `url`, after the
  decompression of the tile: the bytes of an MVT tile for the builds of
  Protomaps. An empty binary when the archive has no such tile (for
  example out of the area of an extract).

  Options:

    * `:headers` - the header fields of each request, for example a key.
  """
  @spec tile(String.t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def tile(url, z, x, y, opts \\ []) when is_binary(url) do
    if valid_tile?(z, x, y) do
      case read_tile(url, z, x, y, opts) do
        # The file changed: one more time, with the new file.
        {:error, :changed} ->
          forget(url)
          read_tile(url, z, x, y, opts)

        result ->
          result
      end
    else
      {:error, :invalid_tile}
    end
  end

  @doc """
  The header of the archive at `url`, with its zoom levels and the types
  of its data.
  """
  @spec header(String.t(), keyword()) :: {:ok, header()} | {:error, term()}
  def header(url, opts \\ []) when is_binary(url) do
    with {:ok, archive} <- open(url, opts), do: {:ok, archive.header}
  end

  @doc "Forgets the parts of the archive at `url` in the cache."
  @spec forget(String.t()) :: :ok
  def forget(url) do
    if cache?() do
      :ets.match_delete(@table, {{:archive, url}, :_})
      :ets.match_delete(@table, {{:leaf, url, :_, :_}, :_, :_})
    end

    :ok
  end

  @doc """
  The tile ID of a tile: the number of the tiles of the zoom levels before
  it, and then the place of the tile on the Hilbert curve of its level.

      iex> LiveMap.PMTiles.tile_id(0, 0, 0)
      0
      iex> Enum.map([{0, 0}, {0, 1}, {1, 1}, {1, 0}], fn {x, y} -> LiveMap.PMTiles.tile_id(1, x, y) end)
      [1, 2, 3, 4]
      iex> LiveMap.PMTiles.tile_id(2, 0, 0)
      5
  """
  @spec tile_id(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def tile_id(z, x, y) do
    unless valid_tile?(z, x, y), do: raise(ArgumentError, "invalid tile #{z}/#{x}/#{y}")
    first_id(z) + hilbert((1 <<< z) >>> 1, x, y, 0)
  end

  @doc """
  The tile `{z, x, y}` of a tile ID, the reverse of `tile_id/3`.

      iex> LiveMap.PMTiles.tile_of(0)
      {0, 0, 0}
      iex> LiveMap.PMTiles.tile_of(LiveMap.PMTiles.tile_id(12, 3242, 1781))
      {12, 3242, 1781}
  """
  @spec tile_of(non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def tile_of(id) when is_integer(id) and id >= 0 do
    z = zoom_of(id, 0)
    {x, y} = point_of(id - first_id(z), 1, 1 <<< z, 0, 0)
    {z, x, y}
  end

  defp valid_tile?(z, x, y) do
    is_integer(z) and z >= 0 and z <= @max_zoom and is_integer(x) and is_integer(y) and
      x >= 0 and y >= 0 and x < 1 <<< z and y < 1 <<< z
  end

  # The tiles of the zoom levels before `z`: (4^z - 1) / 3.
  defp first_id(z), do: div((1 <<< (2 * z)) - 1, 3)

  defp hilbert(0, _x, _y, d), do: d

  defp hilbert(s, x, y, d) do
    rx = if x >= s, do: 1, else: 0
    ry = if y >= s, do: 1, else: 0
    {x, y} = rotate(s, x - rx * s, y - ry * s, rx, ry)
    hilbert(s >>> 1, x, y, d + s * s * bxor(3 * rx, ry))
  end

  defp rotate(s, x, y, 1, 0), do: {s - 1 - y, s - 1 - x}
  defp rotate(_s, x, y, 0, 0), do: {y, x}
  defp rotate(_s, x, y, _rx, _ry), do: {x, y}

  defp zoom_of(id, z) do
    if z < @max_zoom and first_id(z + 1) <= id, do: zoom_of(id, z + 1), else: z
  end

  defp point_of(_t, s, size, x, y) when s >= size, do: {x, y}

  defp point_of(t, s, size, x, y) do
    rx = band(t >>> 1, 1)
    ry = bxor(band(t, 1), rx)
    {x, y} = rotate(s, x, y, rx, ry)
    point_of(t >>> 2, s <<< 1, size, x + s * rx, y + s * ry)
  end

  ## The archive and its directories

  defp read_tile(url, z, x, y, opts) do
    with {:ok, archive} <- open(url, opts) do
      header = archive.header

      if z < header.min_zoom or z > header.max_zoom do
        {:ok, ""}
      else
        case find(archive, tile_id(z, x, y), opts) do
          # No tile: no data to decompress.
          {:ok, nil} ->
            {:ok, ""}

          {:ok, place} ->
            with {:ok, data} <- tile_data(archive, place, opts),
                 do: decompress(data, header.tile_compression)

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  defp open(url, opts) do
    case lookup({:archive, url}) do
      [{_key, archive}] ->
        if fresh?(archive), do: {:ok, archive}, else: load(url, opts)

      [] ->
        load(url, opts)
    end
  end

  # A local file that changed has a new size or time.
  defp fresh?(%{url: "file://" <> path, etag: etag}), do: file_etag(path) == etag
  defp fresh?(_archive), do: true

  defp load(url, opts) do
    forget(url)

    with {:ok, first, etag} <- read(url, 0, @first_bytes, nil, opts),
         {:ok, header} <- read_header(first),
         :ok <- check_type(header),
         {:ok, root_bytes} <- root_bytes(url, first, header, etag, opts),
         {:ok, raw} <- decompress(root_bytes, header.internal_compression),
         {:ok, root} <- read_directory(raw) do
      archive = %{url: url, etag: etag, header: header, root: root}
      store({{:archive, url}, archive})
      {:ok, archive}
    end
  end

  defp root_bytes(url, first, %{root_offset: offset, root_length: length}, etag, opts) do
    if offset + length <= byte_size(first),
      do: {:ok, binary_part(first, offset, length)},
      else: read_exact(url, offset, length, etag, opts)
  end

  @doc false
  @spec read_header(binary()) :: {:ok, header()} | {:error, term()}
  def read_header(<<"PMTiles", 3, fields::binary-size(119), _rest::binary>>) do
    <<root_offset::little-64, root_length::little-64, metadata_offset::little-64,
      metadata_length::little-64, leaf_offset::little-64, leaf_length::little-64,
      data_offset::little-64, data_length::little-64, _addressed::little-64, _entries::little-64,
      _contents::little-64, _clustered, internal_compression, tile_compression, tile_type,
      min_zoom, max_zoom, _rest::binary>> = fields

    {:ok,
     %{
       root_offset: root_offset,
       root_length: root_length,
       metadata_offset: metadata_offset,
       metadata_length: metadata_length,
       leaf_offset: leaf_offset,
       leaf_length: leaf_length,
       data_offset: data_offset,
       data_length: data_length,
       internal_compression: internal_compression,
       tile_compression: tile_compression,
       tile_type: tile_type,
       min_zoom: min_zoom,
       max_zoom: max_zoom
     }}
  end

  def read_header(<<"PMTiles", version, _rest::binary>>) when version != 3,
    do: {:error, {:unsupported_version, version}}

  def read_header(<<"PMTiles", _rest::binary>>), do: {:error, :truncated_header}
  def read_header(_bytes), do: {:error, :not_pmtiles}

  # LiveMap draws the vector tiles of an archive (type 1, MVT).
  defp check_type(%{tile_type: 1}), do: :ok
  defp check_type(%{tile_type: type}), do: {:error, {:unsupported_tile_type, type}}

  # The place of a tile in the data of the tiles: the root directory, then
  # at most 3 levels of leaf directories.
  defp find(archive, id, opts), do: find(archive, archive.root, id, 0, opts)

  defp find(archive, directory, id, depth, opts) do
    case last_at_or_before(directory, id) do
      -1 ->
        {:ok, nil}

      index ->
        {first, run, length, offset} = entry(directory, index)

        cond do
          run > 0 and id - first < run ->
            {:ok, {offset, length}}

          run > 0 ->
            {:ok, nil}

          depth >= @max_depth ->
            {:error, :directories_too_deep}

          true ->
            with {:ok, leaf} <- leaf(archive, offset, length, opts) do
              find(archive, leaf, id, depth + 1, opts)
            end
        end
    end
  end

  defp leaf(archive, offset, length, opts) do
    key = {:leaf, archive.url, archive.etag, offset}

    case lookup(key) do
      [{_key, directory, _time}] ->
        {:ok, directory}

      [] ->
        header = archive.header

        if offset + length > header.leaf_length do
          {:error, :leaf_out_of_range}
        else
          with {:ok, bytes} <-
                 read_exact(archive.url, header.leaf_offset + offset, length, archive.etag, opts),
               {:ok, raw} <- decompress(bytes, header.internal_compression),
               {:ok, directory} <- read_directory(raw) do
            keep_leaf(key, directory)
            {:ok, directory}
          end
        end
    end
  end

  defp tile_data(archive, {offset, length}, opts) do
    header = archive.header

    if offset + length > header.data_length,
      do: {:error, :tile_out_of_range},
      else: read_exact(archive.url, header.data_offset + offset, length, archive.etag, opts)
  end

  @doc false
  # A directory after decompression: the number of entries, then the
  # columns of varints: the deltas of the tile IDs, the run lengths, the
  # lengths, and the offsets (0 for the offset after the entry before,
  # else the offset + 1).
  @spec read_directory(binary()) :: {:ok, directory()} | {:error, term()}
  def read_directory(bytes) do
    {count, rest} = varint!(bytes)
    if count > @max_entries, do: throw({:pmtiles, :directory_too_large})
    # Each entry has 4 varints of at least one byte.
    if count * 4 > byte_size(rest), do: throw({:pmtiles, :truncated_directory})

    {ids, rest} = ids(rest, count, 0, 0, <<>>)
    {runs, rest} = numbers(rest, count, <<>>)
    {lengths, rest} = lengths(rest, count, <<>>)
    {offsets, _rest} = offsets(rest, 0, count, lengths, 0, 0, <<>>)
    {:ok, %{count: count, ids: ids, runs: runs, lengths: lengths, offsets: offsets}}
  catch
    {:pmtiles, reason} -> {:error, reason}
  end

  defp ids(rest, 0, _index, _last, acc), do: {acc, rest}

  defp ids(rest, n, index, last, acc) do
    {delta, rest} = varint!(rest)
    if index > 0 and delta == 0, do: throw({:pmtiles, :unordered_directory})
    id = last + delta
    if id >= 1 <<< 64, do: throw({:pmtiles, :tile_id_too_large})
    ids(rest, n - 1, index + 1, id, <<acc::binary, id::64>>)
  end

  defp numbers(rest, 0, acc), do: {acc, rest}

  defp numbers(rest, n, acc) do
    {value, rest} = varint!(rest)
    numbers(rest, n - 1, <<acc::binary, value::64>>)
  end

  defp lengths(rest, 0, acc), do: {acc, rest}

  defp lengths(rest, n, acc) do
    {value, rest} = varint!(rest)
    if value == 0 or value >= 1 <<< 32, do: throw({:pmtiles, :invalid_length})
    lengths(rest, n - 1, <<acc::binary, value::32>>)
  end

  defp offsets(rest, _index, 0, _lengths, _offset, _length, acc), do: {acc, rest}

  defp offsets(rest, index, n, lengths, previous, previous_length, acc) do
    {value, rest} = varint!(rest)

    offset =
      cond do
        index > 0 and value == 0 -> previous + previous_length
        value == 0 -> throw({:pmtiles, :invalid_offset})
        true -> value - 1
      end

    <<length::32>> = binary_part(lengths, index * 4, 4)
    offsets(rest, index + 1, n - 1, lengths, offset, length, <<acc::binary, offset::64>>)
  end

  defp varint!(bytes), do: varint(bytes, 0, 0)

  defp varint(<<0::1, byte::7, rest::binary>>, shift, acc), do: {acc ||| byte <<< shift, rest}

  defp varint(<<1::1, byte::7, rest::binary>>, shift, acc) when shift < 63,
    do: varint(rest, shift + 7, acc ||| byte <<< shift)

  defp varint(<<>>, _shift, _acc), do: throw({:pmtiles, :truncated_directory})
  defp varint(_bytes, _shift, _acc), do: throw({:pmtiles, :varint_too_long})

  # The index of the last entry with a tile ID that is not more than `id`,
  # or -1.
  defp last_at_or_before(%{count: count, ids: ids}, id), do: search(ids, id, 0, count - 1)

  defp search(_ids, _id, low, high) when low > high, do: high

  defp search(ids, id, low, high) do
    middle = div(low + high, 2)
    <<value::64>> = binary_part(ids, middle * 8, 8)

    if value <= id,
      do: search(ids, id, middle + 1, high),
      else: search(ids, id, low, middle - 1)
  end

  defp entry(directory, index) do
    <<id::64>> = binary_part(directory.ids, index * 8, 8)
    <<run::64>> = binary_part(directory.runs, index * 8, 8)
    <<length::32>> = binary_part(directory.lengths, index * 4, 4)
    <<offset::64>> = binary_part(directory.offsets, index * 8, 8)
    {id, run, length, offset}
  end

  # The compressions of the header: 1 none, 2 gzip. The specification
  # also has brotli (3) and zstd (4).
  defp decompress(bytes, 1), do: {:ok, bytes}

  defp decompress(bytes, 2) do
    {:ok, :zlib.gunzip(bytes)}
  rescue
    ErlangError -> {:error, :bad_gzip}
  end

  defp decompress(_bytes, compression), do: {:error, {:unsupported_compression, compression}}

  ## The cache

  defp cache?, do: :ets.whereis(@table) != :undefined

  defp lookup(key), do: if(cache?(), do: :ets.lookup(@table, key), else: [])

  defp store(entry), do: if(cache?(), do: :ets.insert(@table, entry))

  # A leaf directory goes into the cache with its time; the oldest one
  # goes when the cache has its limit.
  defp keep_leaf(key, directory) do
    if cache?() do
      limit = Application.get_env(:live_map, :pmtiles_leaf_cache, @default_leaf_cache)
      leaves = :ets.select(@table, [{{{:leaf, :_, :_, :_}, :_, :"$1"}, [], [:"$_"]}])

      if length(leaves) >= limit do
        leaves
        |> Enum.sort_by(fn {_key, _directory, time} -> time end)
        |> Enum.take(length(leaves) - limit + 1)
        |> Enum.each(fn {old, _directory, _time} -> :ets.delete(@table, old) end)
      end

      if limit > 0,
        do: :ets.insert(@table, {key, directory, System.monotonic_time()})
    end
  end

  ## The reads

  defp read_exact(url, offset, length, etag, opts) do
    case read(url, offset, length, etag, opts) do
      {:ok, bytes, _etag} when byte_size(bytes) == length -> {:ok, bytes}
      {:ok, _bytes, _etag} -> {:error, :short_read}
      {:error, reason} -> {:error, reason}
    end
  end

  # The bytes from `offset`, at most `length` of them, and the ETag of the
  # file.
  defp read("file://" <> path, offset, length, _etag, _opts) do
    with {:ok, file} <- :file.open(path, [:read, :binary, :raw]) do
      try do
        case :file.pread(file, offset, length) do
          {:ok, bytes} -> {:ok, bytes, file_etag(path)}
          :eof -> {:ok, "", file_etag(path)}
          {:error, reason} -> {:error, reason}
        end
      after
        :file.close(file)
      end
    end
  end

  defp read(url, offset, length, etag, opts) do
    unless Code.ensure_loaded?(@req_module) do
      raise ArgumentError, "PMTiles over HTTP require the optional Req dependency"
    end

    headers =
      [{"range", "bytes=#{offset}-#{offset + length - 1}"}] ++
        if(etag, do: [{"if-match", etag}], else: []) ++ user_headers(opts)

    options = [
      headers: headers,
      compressed: false,
      raw: true,
      decode_body: false,
      http_errors: :return,
      retry: false,
      into: collect(length)
    ]

    case apply(@req_module, :get, [url, options]) do
      {:ok, %{status: 206} = response} ->
        {:ok, body(response, length), strong_etag(response)}

      # A server with no ranges gives the file from its start: enough for
      # the first bytes of a small file only.
      {:ok, %{status: 200} = response} when offset == 0 ->
        {:ok, body(response, length), strong_etag(response)}

      {:ok, %{status: 200}} ->
        {:error, :no_ranges}

      {:ok, %{status: 412}} ->
        {:error, :changed}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp user_headers(opts) do
    headers = Keyword.get(opts, :headers, [])

    if Enum.any?(headers, fn {name, _value} -> String.downcase(name) == "user-agent" end),
      do: headers,
      else: [{"user-agent", @default_user_agent} | headers]
  end

  # The body stops at `length` bytes, also from a server that gives more.
  defp collect(length) do
    fn {:data, data}, {request, response} ->
      body = IO.iodata_to_binary([response.body || "", data])
      response = %{response | body: body}

      if byte_size(body) >= length,
        do: {:halt, {request, response}},
        else: {:cont, {request, response}}
    end
  end

  defp body(response, length) do
    body = IO.iodata_to_binary(response.body || "")
    if byte_size(body) > length, do: binary_part(body, 0, length), else: body
  end

  # Only a strong ETag works with If-Match.
  defp strong_etag(response) do
    case response.headers["etag"] do
      [<<"\"", _rest::binary>> = etag | _others] -> etag
      _none -> nil
    end
  end

  defp file_etag(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{size: size, mtime: mtime}} -> "#{size}-#{mtime}"
      {:error, _reason} -> nil
    end
  end
end
