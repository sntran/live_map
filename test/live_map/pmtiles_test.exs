defmodule LiveMap.PMTilesTest do
  # The reader of the PMTiles archives: the tile IDs, the directories, the
  # reads of ranges over HTTP and in local files, and the cache.
  use ExUnit.Case, async: false
  use ExUnitProperties

  import Bitwise

  alias LiveMap.PMTiles
  alias LiveMap.TestPMTiles
  alias LiveMap.TestRangeServer

  doctest LiveMap.PMTiles

  @fixture Path.expand("../fixtures/protomaps_ha_giang.pmtiles", __DIR__)
  @hashes Path.expand("../fixtures/protomaps_ha_giang.json", __DIR__)

  setup do
    leaf_cache = Application.get_env(:live_map, :pmtiles_leaf_cache)

    on_exit(fn ->
      if is_nil(leaf_cache),
        do: Application.delete_env(:live_map, :pmtiles_leaf_cache),
        else: Application.put_env(:live_map, :pmtiles_leaf_cache, leaf_cache)
    end)
  end

  defp file_url(bytes) do
    path =
      Path.join(System.tmp_dir!(), "live_map_#{System.unique_integer([:positive])}.pmtiles")

    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    "file://" <> path
  end

  defp serve(bytes, opts \\ []) do
    server = TestRangeServer.start_link(bytes, opts)
    on_exit(fn -> TestRangeServer.stop(server) end)
    # A new server can have the port of a server of before.
    PMTiles.forget(server.url)
    server
  end

  defp read(url, id, opts \\ []) do
    {z, x, y} = PMTiles.tile_of(id)
    PMTiles.tile(url, z, x, y, opts)
  end

  # The entries of a directory of the reader, as the writer takes them.
  defp entries(%{count: count} = directory) do
    for index <- 0..(count - 1)//1 do
      <<id::64>> = binary_part(directory.ids, index * 8, 8)
      <<run::64>> = binary_part(directory.runs, index * 8, 8)
      <<length::32>> = binary_part(directory.lengths, index * 4, 4)
      <<offset::64>> = binary_part(directory.offsets, index * 8, 8)
      {id, run, offset, length}
    end
  end

  describe "the tile IDs" do
    property "a tile ID gives its tile again" do
      check all(
              z <- integer(0..31),
              x <- integer(0..((1 <<< z) - 1)),
              y <- integer(0..((1 <<< z) - 1))
            ) do
        id = PMTiles.tile_id(z, x, y)
        assert PMTiles.tile_of(id) == {z, x, y}
        # The IDs of a zoom level come after all the IDs of the levels before.
        assert id >= div((1 <<< (2 * z)) - 1, 3)
        assert id < div((1 <<< (2 * (z + 1))) - 1, 3)
      end
    end

    property "the next ID on a zoom level is a tile next to the tile" do
      check all(
              z <- integer(1..31),
              d <- integer(0..((1 <<< (2 * z)) - 2))
            ) do
        id = div((1 <<< (2 * z)) - 1, 3) + d
        {^z, x1, y1} = PMTiles.tile_of(id)
        {^z, x2, y2} = PMTiles.tile_of(id + 1)
        assert abs(x1 - x2) + abs(y1 - y2) == 1
      end
    end

    test "a tile out of its zoom level is not valid" do
      assert_raise ArgumentError, ~r/invalid tile 1\/2\/0/, fn -> PMTiles.tile_id(1, 2, 0) end
      assert {:error, :invalid_tile} = PMTiles.tile("file:///none.pmtiles", 32, 0, 0)
      assert {:error, :invalid_tile} = PMTiles.tile("file:///none.pmtiles", 2, -1, 0)
      assert {:error, :invalid_tile} = PMTiles.tile("file:///none.pmtiles", 2, 0, 4)
      assert {:error, :invalid_tile} = PMTiles.tile("file:///none.pmtiles", 2, 0.5, 0)
    end
  end

  describe "the directories" do
    property "a directory gives its entries again" do
      check all(
              ids <- uniq_list_of(integer(0..1_000_000), min_length: 1, max_length: 40),
              columns <-
                list_of(
                  tuple({integer(0..5), integer(1..100_000), integer(0..10_000_000)}),
                  length: length(ids)
                )
            ) do
        written =
          ids
          |> Enum.sort()
          |> Enum.zip_with(columns, fn id, {run, length, offset} -> {id, run, offset, length} end)

        assert {:ok, directory} = PMTiles.read_directory(TestPMTiles.directory(written, 1))
        assert directory.count == length(written)
        assert entries(directory) == written
      end
    end

    property "a directory of random bytes gives a result or an error" do
      check all(bytes <- binary(max_length: 64)) do
        assert match?({:ok, %{}}, PMTiles.read_directory(bytes)) or
                 match?({:error, _reason}, PMTiles.read_directory(bytes))
      end
    end

    test "an offset of 0 is the end of the tile before" do
      bytes = TestPMTiles.directory([{1, 1, 0, 3}, {2, 1, 3, 4}, {3, 1, 0, 5}], 1)

      assert {:ok, directory} = PMTiles.read_directory(bytes)
      assert entries(directory) == [{1, 1, 0, 3}, {2, 1, 3, 4}, {3, 1, 0, 5}]
    end

    test "a directory that is not valid gives an error" do
      varint = &TestPMTiles.varint/1

      cases = [
        {varint.(1_000_001), :directory_too_large},
        {<<>>, :truncated_directory},
        {<<2, 0, 1, 1>>, :truncated_directory},
        {<<1, 0x80, 0x80, 0x80, 0x80>>, :truncated_directory},
        {<<2, 1, 0, 1, 1, 1, 1, 1, 0>>, :unordered_directory},
        {<<1>> <> varint.(1 <<< 64) <> <<1, 1, 1>>, :tile_id_too_large},
        {<<1, 0, 1, 0, 1>>, :invalid_length},
        {<<1, 0, 1>> <> varint.(1 <<< 32) <> <<1>>, :invalid_length},
        {<<1, 0, 1, 1, 0>>, :invalid_offset},
        {<<1>> <> :binary.copy(<<0xFF>>, 10) <> <<0, 1, 1, 1>>, :varint_too_long}
      ]

      for {bytes, reason} <- cases do
        assert PMTiles.read_directory(bytes) == {:error, reason}
      end
    end
  end

  describe "the tiles of an archive" do
    test "a root directory with all the tiles" do
      tiles = [{{0, 0, 0}, "zero"}, {{1, 0, 0}, "one"}, {{1, 1, 1}, "three"}, {{2, 3, 3}, "far"}]
      bytes = tiles |> Enum.map(fn {{z, x, y}, data} -> {PMTiles.tile_id(z, x, y), data} end)
      url = file_url(TestPMTiles.build(bytes, max_zoom: 2))

      for {{z, x, y}, data} <- tiles do
        assert PMTiles.tile(url, z, x, y) == {:ok, data}
      end

      # A tile with no data, and a tile above the highest zoom level.
      assert PMTiles.tile(url, 1, 0, 1) == {:ok, ""}
      assert PMTiles.tile(url, 2, 0, 0) == {:ok, ""}
      assert PMTiles.tile(url, 3, 0, 0) == {:ok, ""}
    end

    test "a tile before the first entry, and a tile below the lowest zoom level" do
      url = file_url(TestPMTiles.build([{1, "one"}, {5, "five"}], max_zoom: 2))

      assert read(url, 0) == {:ok, ""}
      assert read(url, 1) == {:ok, "one"}
      assert read(url, 5) == {:ok, "five"}

      url = file_url(TestPMTiles.build([{1, "one"}, {5, "five"}], min_zoom: 2, max_zoom: 2))
      assert read(url, 1) == {:ok, ""}
      assert read(url, 5) == {:ok, "five"}
    end

    test "the leaf directories" do
      tiles = for id <- 0..20, do: {id, "tile #{id}"}
      server = serve(TestPMTiles.build(tiles, leaf_size: 3, max_zoom: 2))

      for {id, data} <- tiles do
        assert read(server.url, id) == {:ok, data}
      end

      # Each tile after its leaf directory needs one request.
      PMTiles.forget(server.url)
      TestRangeServer.clear(server)
      assert read(server.url, 0) == {:ok, "tile 0"}
      assert [first, leaf, data] = TestRangeServer.requests(server)
      assert first.range == "bytes=0-16383"
      assert first.if_match == nil
      assert leaf.if_match =~ ~r/^"[0-9a-f]{32}"$/
      assert data.if_match == leaf.if_match

      TestRangeServer.clear(server)
      assert read(server.url, 2) == {:ok, "tile 2"}
      assert length(TestRangeServer.requests(server)) == 1

      TestRangeServer.clear(server)
      assert read(server.url, 3) == {:ok, "tile 3"}
      assert length(TestRangeServer.requests(server)) == 2
    end

    test "the runs of the same tile" do
      tiles = for(id <- 5..10, do: {id, "sea"}) ++ [{11, "land"}]
      archive = TestPMTiles.build(tiles, runs: true, max_zoom: 2)
      url = file_url(archive)

      for {id, data} <- tiles do
        assert read(url, id) == {:ok, data}
      end

      assert read(url, 12) == {:ok, ""}

      {:ok, header} = PMTiles.header(url)
      root = binary_part(archive, header.root_offset, header.root_length)
      {:ok, directory} = PMTiles.read_directory(:zlib.gunzip(root))
      assert [{5, 6, _offset, _length}, {11, 1, _next, _size}] = entries(directory)
    end

    test "tiles and directories with no compression" do
      tiles = for id <- 0..4, do: {id, "plain #{id}"}
      url = file_url(TestPMTiles.build(tiles, leaf_size: 2, internal: 1, compression: 1))

      for {id, data} <- tiles do
        assert read(url, id) == {:ok, data}
      end

      assert {:ok, %{internal_compression: 1, tile_compression: 1}} = PMTiles.header(url)
    end

    test "a root directory after the first 16 KiB" do
      tiles = for id <- 0..4_999, do: {id, <<rem(id, 256)>>}
      archive = TestPMTiles.build(tiles, internal: 1, compression: 1, max_zoom: 6)
      server = serve(archive)

      assert {:ok, header} = PMTiles.header(server.url)
      assert header.root_length > 16_384

      assert read(server.url, 4_321) == {:ok, <<rem(4_321, 256)>>}

      assert [_first, root, _data] = TestRangeServer.requests(server)
      assert root.range == "bytes=127-#{127 + header.root_length - 1}"
    end

    test "the header of an archive" do
      assert {:ok, header} = PMTiles.header("file://" <> @fixture)

      assert %{
               min_zoom: 12,
               max_zoom: 14,
               tile_type: 1,
               tile_compression: 2,
               internal_compression: 2
             } = header
    end

    test "the tiles of an extract of the planet of Protomaps" do
      url = "file://" <> @fixture

      for {tile, hash} <- @hashes |> File.read!() |> Jason.decode!() do
        [z, x, y] = tile |> String.split("/") |> Enum.map(&String.to_integer/1)
        assert {:ok, data} = PMTiles.tile(url, z, x, y)
        assert Base.encode16(:crypto.hash(:sha256, data), case: :lower) == hash
      end

      # Out of the area of the extract, and out of its zoom levels.
      assert PMTiles.tile(url, 14, 0, 0) == {:ok, ""}
      assert PMTiles.tile(url, 15, 25_940, 14_250) == {:ok, ""}
      assert PMTiles.tile(url, 11, 1_621, 890) == {:ok, ""}
    end

    test "many readers at the same time" do
      url = "file://" <> @fixture
      PMTiles.forget(url)
      expected = PMTiles.tile(url, 14, 12_969, 7_124)
      PMTiles.forget(url)

      results =
        1..64
        |> Task.async_stream(fn _n -> PMTiles.tile(url, 14, 12_969, 7_124) end,
          max_concurrency: 16
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.uniq(results) == [expected]
    end
  end

  describe "the archives that are not valid" do
    test "a file that is not an archive of version 3" do
      tiles = [{0, "zero"}]

      assert PMTiles.tile(file_url("not a map"), 0, 0, 0) == {:error, :not_pmtiles}
      assert PMTiles.tile(file_url(""), 0, 0, 0) == {:error, :not_pmtiles}

      assert PMTiles.tile(file_url("PMTiles" <> <<3, 0, 0>>), 0, 0, 0) ==
               {:error, :truncated_header}

      assert PMTiles.tile(file_url(TestPMTiles.build(tiles, version: 2)), 0, 0, 0) ==
               {:error, {:unsupported_version, 2}}
    end

    test "the compressions and the types that the reader does not know" do
      tiles = [{0, "zero"}]

      assert PMTiles.tile(file_url(TestPMTiles.build(tiles, compression: 3)), 0, 0, 0) ==
               {:error, {:unsupported_compression, 3}}

      assert PMTiles.tile(file_url(TestPMTiles.build(tiles, internal: 3)), 0, 0, 0) ==
               {:error, {:unsupported_compression, 3}}

      assert PMTiles.tile(file_url(TestPMTiles.build(tiles, type: 2)), 0, 0, 0) ==
               {:error, {:unsupported_tile_type, 2}}
    end

    test "a tile that is not a valid gzip" do
      root = TestPMTiles.directory([{0, 1, 0, 8}])
      url = file_url(TestPMTiles.assemble(root, "", "not gzip"))

      assert PMTiles.tile(url, 0, 0, 0) == {:error, :bad_gzip}
    end

    test "positions out of the sections of the file" do
      root = TestPMTiles.directory([{0, 0, 10, 5}])
      url = file_url(TestPMTiles.assemble(root, "", "data"))
      assert PMTiles.tile(url, 0, 0, 0) == {:error, :leaf_out_of_range}

      root = TestPMTiles.directory([{0, 1, 4, 10}])
      url = file_url(TestPMTiles.assemble(root, "", "short"))
      assert PMTiles.tile(url, 0, 0, 0) == {:error, :tile_out_of_range}

      # A file that is shorter than its header says.
      root = TestPMTiles.directory([{0, 1, 0, 10}], 1)
      archive = TestPMTiles.assemble(root, "", "0123456789", internal: 1, compression: 1)
      url = file_url(binary_part(archive, 0, byte_size(archive) - 4))
      assert PMTiles.tile(url, 0, 0, 0) == {:error, :short_read}
    end

    test "leaf directories in a loop" do
      # A leaf directory of 5 bytes with one entry: itself.
      leaf = TestPMTiles.directory([{0, 0, 0, 5}], 1)
      assert byte_size(leaf) == 5

      url = file_url(TestPMTiles.assemble(leaf, leaf, "", internal: 1))
      assert PMTiles.tile(url, 0, 0, 0) == {:error, :directories_too_deep}
    end

    test "a local file that is not there" do
      assert PMTiles.tile("file:///none/live_map.pmtiles", 0, 0, 0) == {:error, :enoent}
    end
  end

  describe "the reads over HTTP" do
    test "a file that changes at its URL" do
      old = TestPMTiles.build([{0, "old"}, {1, "old one"}], max_zoom: 1)
      new = TestPMTiles.build([{0, "a new tile"}, {1, "new one"}], max_zoom: 1)
      server = serve(old)

      assert read(server.url, 0) == {:ok, "old"}
      [%{if_match: nil}, %{if_match: old_etag}] = TestRangeServer.requests(server)

      TestRangeServer.replace(server, new)
      TestRangeServer.clear(server)

      assert read(server.url, 1) == {:ok, "new one"}

      assert [%{if_match: ^old_etag}, %{if_match: nil}, %{if_match: new_etag}] =
               TestRangeServer.requests(server)

      assert new_etag != old_etag
      assert read(server.url, 0) == {:ok, "a new tile"}
    end

    test "no If-Match with a weak ETag or with no ETag" do
      tiles = [{0, "zero"}, {1, "one"}]

      for kind <- [:weak, :none] do
        server = serve(TestPMTiles.build(tiles, max_zoom: 1), etag: kind)

        assert read(server.url, 0) == {:ok, "zero"}
        assert read(server.url, 1) == {:ok, "one"}
        assert Enum.all?(TestRangeServer.requests(server), &is_nil(&1.if_match))
      end
    end

    test "a server that gives no ranges" do
      server = serve(TestPMTiles.build([{0, "zero"}]), ranges: false)
      assert PMTiles.tile(server.url, 0, 0, 0) == {:error, :no_ranges}

      # Only the first 16 KiB of a large file.
      tiles = for id <- 0..4_999, do: {id, <<rem(id, 256)>>}
      archive = TestPMTiles.build(tiles, internal: 1, compression: 1, max_zoom: 6)
      server = serve(archive, ranges: false)
      assert PMTiles.tile(server.url, 0, 0, 0) == {:error, :no_ranges}
    end

    test "the status of a server, and a server that does not answer" do
      server = LiveMap.TestTileServer.start_link()
      on_exit(fn -> LiveMap.TestTileServer.stop(server) end)

      assert PMTiles.tile(server.base_url <> "/none.pmtiles", 0, 0, 0) ==
               {:error, {:http_status, 404}}

      assert {:error, %{__exception__: true}} =
               PMTiles.tile("http://127.0.0.1:1/map.pmtiles", 0, 0, 0)
    end

    test "the header fields of the requests" do
      server = serve(TestPMTiles.build([{0, "zero"}, {1, "one"}], max_zoom: 1))

      assert read(server.url, 0, headers: [{"x-key", "secret"}]) == {:ok, "zero"}

      for request <- TestRangeServer.requests(server) do
        assert request.user_agent =~ ~r/^LiveMap\//
        assert {"x-key", "secret"} in request.headers
      end

      TestRangeServer.clear(server)
      assert read(server.url, 1, headers: [{"User-Agent", "Phuot"}]) == {:ok, "one"}
      assert [%{user_agent: "Phuot"}] = TestRangeServer.requests(server)
    end
  end

  describe "the cache" do
    test "the cache keeps some leaf directories" do
      Application.put_env(:live_map, :pmtiles_leaf_cache, 1)
      tiles = for id <- 0..5, do: {id, "tile #{id}"}
      server = serve(TestPMTiles.build(tiles, leaf_size: 2, max_zoom: 1))

      assert read(server.url, 0) == {:ok, "tile 0"}

      # The leaf of the tiles 2 and 3 takes the place of the leaf of 0 and 1.
      TestRangeServer.clear(server)
      assert read(server.url, 2) == {:ok, "tile 2"}
      assert length(TestRangeServer.requests(server)) == 2

      TestRangeServer.clear(server)
      assert read(server.url, 0) == {:ok, "tile 0"}
      assert length(TestRangeServer.requests(server)) == 2

      TestRangeServer.clear(server)
      assert read(server.url, 1) == {:ok, "tile 1"}
      assert length(TestRangeServer.requests(server)) == 1
    end

    test "no leaf directories in the cache" do
      Application.put_env(:live_map, :pmtiles_leaf_cache, 0)
      tiles = for id <- 0..3, do: {id, "tile #{id}"}
      server = serve(TestPMTiles.build(tiles, leaf_size: 2, max_zoom: 1))

      assert read(server.url, 0) == {:ok, "tile 0"}
      TestRangeServer.clear(server)
      assert read(server.url, 1) == {:ok, "tile 1"}
      assert length(TestRangeServer.requests(server)) == 2
    end

    test "a local file that changes" do
      path =
        Path.join(System.tmp_dir!(), "live_map_#{System.unique_integer([:positive])}.pmtiles")

      on_exit(fn -> File.rm(path) end)
      url = "file://" <> path

      File.write!(path, TestPMTiles.build([{0, "old"}]))
      assert PMTiles.tile(url, 0, 0, 0) == {:ok, "old"}

      File.write!(path, TestPMTiles.build([{0, "a new tile"}]))
      assert PMTiles.tile(url, 0, 0, 0) == {:ok, "a new tile"}

      File.rm!(path)
      assert PMTiles.tile(url, 0, 0, 0) == {:error, :enoent}
    end

    test "the reads with no cache" do
      :ok = Supervisor.terminate_child(LiveMap.Supervisor, LiveMap.PMTiles.Cache)

      try do
        url = "file://" <> @fixture
        assert {:ok, data} = PMTiles.tile(url, 14, 12_969, 7_124)
        assert byte_size(data) > 0
        assert PMTiles.forget(url) == :ok

        tiles = for id <- 0..3, do: {id, "tile #{id}"}
        url = file_url(TestPMTiles.build(tiles, leaf_size: 2, max_zoom: 1))
        assert read(url, 3) == {:ok, "tile 3"}
      after
        {:ok, _pid} = Supervisor.restart_child(LiveMap.Supervisor, LiveMap.PMTiles.Cache)
      end
    end
  end
end
