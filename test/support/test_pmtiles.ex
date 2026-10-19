defmodule LiveMap.TestPMTiles do
  @moduledoc false
  # A writer of small PMTiles archives of version 3 for the tests of
  # LiveMap.PMTiles: a root directory, or a root directory of leaf
  # directories, with the compressions and the types of the header.

  import Bitwise

  @doc """
  An archive of `tiles`, a list of `{tile_id, data}`. Options:

    * `:leaf_size` - the entries of each leaf directory; none by default.
    * `:internal` - the compression of the directories: 1 none, 2 gzip.
    * `:compression` - the compression of the tiles: 1 none, 2 gzip.
    * `:type` - the type of the tiles: 1 MVT.
    * `:min_zoom`, `:max_zoom` - the zoom levels of the header.
    * `:runs` - tiles with the same data after each other are one entry.
  """
  def build(tiles, opts \\ []) do
    internal = Keyword.get(opts, :internal, 2)
    compression = Keyword.get(opts, :compression, 2)
    tiles = Enum.sort_by(tiles, &elem(&1, 0))

    {entries, data} =
      tiles
      |> Enum.map(fn {id, bytes} -> {id, compress(bytes, compression)} end)
      |> entries(Keyword.get(opts, :runs, false))

    {root, leaves} =
      case Keyword.get(opts, :leaf_size) do
        nil -> {entries, ""}
        size -> leaves(entries, size, internal)
      end

    assemble(directory(root, internal), leaves, data, Keyword.put(opts, :internal, internal))
  end

  @doc "A file of a root directory, leaf directories and data, as they are."
  def assemble(root, leaves, data, opts \\ []) do
    root_offset = 127
    leaf_offset = root_offset + byte_size(root)
    data_offset = leaf_offset + byte_size(leaves)

    header =
      <<"PMTiles", Keyword.get(opts, :version, 3), root_offset::little-64,
        byte_size(root)::little-64, data_offset + byte_size(data)::little-64, 0::little-64,
        leaf_offset::little-64, byte_size(leaves)::little-64, data_offset::little-64,
        byte_size(data)::little-64, 0::little-64, 0::little-64, 0::little-64, 1,
        Keyword.get(opts, :internal, 2), Keyword.get(opts, :compression, 2),
        Keyword.get(opts, :type, 1), Keyword.get(opts, :min_zoom, 0),
        Keyword.get(opts, :max_zoom, 14), 0::32, 0::32, 0::32, 0::32, 0, 0::32, 0::32>>

    127 = byte_size(header)
    header <> root <> leaves <> data
  end

  @doc """
  A directory of `entries`, `{tile_id, run_length, offset, length}`,
  after the compression `internal`.
  """
  def directory(entries, internal \\ 2) do
    ids =
      entries
      |> Enum.map_reduce(0, fn {id, _run, _offset, _length}, last -> {varint(id - last), id} end)
      |> elem(0)

    runs = Enum.map(entries, fn {_id, run, _offset, _length} -> varint(run) end)
    lengths = Enum.map(entries, fn {_id, _run, _offset, length} -> varint(length) end)

    offsets =
      entries
      |> Enum.map_reduce(nil, fn {_id, _run, offset, length}, next ->
        {if(offset == next, do: varint(0), else: varint(offset + 1)), offset + length}
      end)
      |> elem(0)

    [varint(length(entries)), ids, runs, lengths, offsets]
    |> IO.iodata_to_binary()
    |> compress(internal)
  end

  def varint(value) when value < 128, do: <<value>>
  def varint(value), do: <<1::1, band(value, 127)::7, varint(value >>> 7)::binary>>

  def compress(bytes, 1), do: bytes
  def compress(bytes, 2), do: :zlib.gzip(bytes)
  def compress(bytes, _other), do: bytes

  # The entries of the tiles, and their data one after the other.
  defp entries(tiles, runs?) do
    {entries, {data, _offset}} =
      Enum.map_reduce(tiles, {[], 0}, fn {id, bytes}, {data, offset} ->
        {{id, 1, offset, byte_size(bytes), bytes}, {[data, bytes], offset + byte_size(bytes)}}
      end)

    entries = if runs?, do: merge_runs(entries), else: entries

    {Enum.map(entries, fn {id, run, offset, length, _bytes} -> {id, run, offset, length} end),
     IO.iodata_to_binary(data)}
  end

  # A tile with the data of the tile before it, at the next ID, adds one to
  # its run.
  defp merge_runs(entries) do
    entries
    |> Enum.reduce([], fn
      {id, 1, _offset, _length, bytes}, [{first, run, offset, length, bytes} | rest]
      when id == first + run ->
        [{first, run + 1, offset, length, bytes} | rest]

      entry, acc ->
        [entry | acc]
    end)
    |> Enum.reverse()
  end

  defp leaves(entries, size, internal) do
    {root, {leaves, _offset}} =
      entries
      |> Enum.chunk_every(size)
      |> Enum.map_reduce({[], 0}, fn chunk, {leaves, offset} ->
        leaf = directory(chunk, internal)
        {first, _run, _offset, _length} = hd(chunk)
        {{first, 0, offset, byte_size(leaf)}, {[leaves, leaf], offset + byte_size(leaf)}}
      end)

    {root, IO.iodata_to_binary(leaves)}
  end
end

defmodule LiveMap.TestRangeServer do
  @moduledoc false
  # A server of one file with ranges, an ETag and If-Match, for the tests
  # of LiveMap.PMTiles. It keeps a log of the requests. Options:
  #
  #   * `:ranges` - false to ignore the ranges and give all the file.
  #   * `:etag` - `:strong` (by default), `:weak` or `:none`.

  def start_link(bytes, opts) do
    kind = Keyword.get(opts, :etag, :strong)

    {:ok, state} =
      Agent.start_link(fn ->
        %{
          bytes: bytes,
          kind: kind,
          etag: etag(bytes, kind),
          ranges?: Keyword.get(opts, :ranges, true),
          log: []
        }
      end)

    ref = String.to_atom("live_map_range_server_#{System.unique_integer([:positive])}")
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__.ServerPlug, state, port: 0, ref: ref)
    %{state: state, ref: ref, url: "http://127.0.0.1:#{:ranch.get_port(ref)}/map.pmtiles"}
  end

  def stop(server) do
    _ = Plug.Cowboy.shutdown(server.ref)
    if Process.alive?(server.state), do: Agent.stop(server.state)
  end

  # A new file at the same URL, with a new ETag.
  def replace(server, bytes),
    do: Agent.update(server.state, &%{&1 | bytes: bytes, etag: etag(bytes, &1.kind)})

  def requests(server), do: Agent.get(server.state, &Enum.reverse(&1.log))

  def clear(server), do: Agent.update(server.state, &%{&1 | log: []})

  defp etag(_bytes, :none), do: nil
  defp etag(bytes, :weak), do: "W/" <> etag(bytes, :strong)
  defp etag(bytes, :strong), do: ~s("#{Base.encode16(:crypto.hash(:md5, bytes), case: :lower)}")

  defmodule ServerPlug do
    @moduledoc false
    import Plug.Conn

    def init(state), do: state

    def call(conn, state) do
      %{bytes: bytes, etag: etag, ranges?: ranges?} = Agent.get(state, & &1)
      range = conn |> get_req_header("range") |> List.first()
      match = conn |> get_req_header("if-match") |> List.first()
      agent = conn |> get_req_header("user-agent") |> List.first()
      entry = %{range: range, if_match: match, user_agent: agent, headers: conn.req_headers}
      Agent.update(state, &%{&1 | log: [entry | &1.log]})
      conn = if etag, do: put_resp_header(conn, "etag", etag), else: conn

      cond do
        match != nil and match != etag ->
          send_resp(conn, 412, "changed")

        ranges? and is_binary(range) ->
          [_all, first, last] = Regex.run(~r/^bytes=(\d+)-(\d+)$/, range)
          first = String.to_integer(first)
          last = min(String.to_integer(last), byte_size(bytes) - 1)
          part = binary_part(bytes, first, last - first + 1)

          conn
          |> put_resp_header("content-range", "bytes #{first}-#{last}/#{byte_size(bytes)}")
          |> send_resp(206, part)

        true ->
          send_resp(conn, 200, bytes)
      end
    end
  end
end
