defmodule LiveMap.VectorTile.PlugTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias LiveMap.VectorTile.Plug, as: VectorTilePlug

  setup do
    server = LiveMap.TestTileServer.start_link()

    on_exit(fn ->
      LiveMap.TestTileServer.stop(server)
    end)

    %{server: server}
  end

  test "serves standalone SVG with cache headers and a reusable ETag", %{server: server} do
    put_tile(server, "/0/0/0.mvt", 7)
    config = config(server)

    conn = request(config, :get, "/0/0/0.svg")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/svg+xml; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]
    assert get_resp_header(conn, "vary") == ["accept-encoding"]
    assert get_resp_header(conn, "content-encoding") == []
    assert [etag] = get_resp_header(conn, "etag")
    assert conn.resp_body =~ ~s(<svg xmlns="http://www.w3.org/2000/svg")
    assert conn.resp_body =~ "live-map-shortbread-role-water"

    compressed =
      conn(:get, "/0/0/0.svg")
      |> put_req_header("accept-encoding", "br, gzip")
      |> VectorTilePlug.call(config)

    assert compressed.status == 200
    assert get_resp_header(compressed, "content-encoding") == ["gzip"]
    assert [gzip_etag] = get_resp_header(compressed, "etag")
    assert gzip_etag != etag
    assert byte_size(compressed.resp_body) < byte_size(conn.resp_body)
    assert :zlib.gunzip(compressed.resp_body) == conn.resp_body

    compressed_not_modified =
      conn(:get, "/0/0/0.svg")
      |> put_req_header("accept-encoding", "gzip")
      |> put_req_header("if-none-match", gzip_etag)
      |> VectorTilePlug.call(config)

    assert compressed_not_modified.status == 304
    assert compressed_not_modified.resp_body == ""
    assert get_resp_header(compressed_not_modified, "content-encoding") == ["gzip"]

    identity_validator_for_compressed_request =
      conn(:get, "/0/0/0.svg")
      |> put_req_header("accept-encoding", "gzip")
      |> put_req_header("if-none-match", etag)
      |> VectorTilePlug.call(config)

    assert identity_validator_for_compressed_request.status == 200

    not_modified =
      conn(:get, "/0/0/0.svg")
      |> put_req_header("if-none-match", etag)
      |> VectorTilePlug.call(config)

    assert not_modified.status == 304
    assert not_modified.resp_body == ""

    weak_not_modified =
      conn(:get, "/0/0/0.svg")
      |> put_req_header("if-none-match", "W/#{etag}")
      |> VectorTilePlug.call(config)

    assert weak_not_modified.status == 304
    assert LiveMap.TestTileServer.request_count(server, "/0/0/0.mvt") == 6

    head =
      conn(:head, "/0/0/0.svg")
      |> put_req_header("accept-encoding", "gzip")
      |> VectorTilePlug.call(config)

    assert head.status == 200
    assert head.resp_body == ""
    assert get_resp_header(head, "content-encoding") == ["gzip"]
    assert LiveMap.TestTileServer.request_count(server, "/0/0/0.mvt") == 7
  end

  test "negotiates gzip quality values and can disable endpoint compression", %{server: server} do
    put_tile(server, "/0/0/0.mvt", 11)
    config = config(server)

    for accept_encoding <- [
          "gzip",
          "GZIP; q=0.5",
          "br, *;q=0.25",
          "gzip; level=1",
          "gzip;q=0, gzip;q=0.5"
        ] do
      conn =
        conn(:get, "/0/0/0.svg")
        |> put_req_header("accept-encoding", accept_encoding)
        |> VectorTilePlug.call(config)

      assert get_resp_header(conn, "content-encoding") == ["gzip"]
    end

    for accept_encoding <- [
          "br",
          "gzip;q=0",
          "*;q=0",
          "gzip;q=invalid, *;q=1",
          "gzip;q=2"
        ] do
      conn =
        conn(:get, "/0/0/0.svg")
        |> put_req_header("accept-encoding", accept_encoding)
        |> VectorTilePlug.call(config)

      assert get_resp_header(conn, "content-encoding") == []
    end

    uncompressed =
      conn(:get, "/0/0/0.svg")
      |> put_req_header("accept-encoding", "gzip")
      |> VectorTilePlug.call(config(server, compress: false))

    assert get_resp_header(uncompressed, "content-encoding") == []
    assert uncompressed.resp_body =~ "<svg"
  end

  test "applies configured styles independently", %{server: server} do
    put_tile(server, "/0/0/0.mvt", 3)

    colorful = config(server)

    styled =
      config(server,
        base_style: "detailed",
        styles: [%{"featureType" => "water", "stylers" => [%{"color" => "#010203"}]}]
      )

    assert request(colorful, :get, "/0/0/0.svg").resp_body !=
             request(styled, :get, "/0/0/0.svg").resp_body

    assert request(styled, :get, "/0/0/0.svg").resp_body =~ "#010203"
    assert LiveMap.TestTileServer.request_count(server, "/0/0/0.mvt") == 3
  end

  test "fetches and crops the parent tile when display zoom exceeds source max zoom", %{
    server: server
  } do
    put_tile(server, "/1/1/1.mvt")
    config = config(server, source_max_zoom: 1, max_display_zoom: 3)

    conn = request(config, :get, "/2/3/2.svg")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(viewBox="0.5 0 0.5 0.5")
    assert conn.resp_body =~ ~s(data-live-map-zoom="2")
    assert LiveMap.TestTileServer.request_count(server, "/1/1/1.mvt") == 1
  end

  test "rejects invalid paths and unsupported methods without fetching upstream", %{
    server: server
  } do
    config = config(server, max_display_zoom: 2)

    for path <- [
          "/3/0/0.svg",
          "/1/2/0.svg",
          "/1/0/2.svg",
          "/1/0/0.png",
          "/1/0/0.svg.svg",
          "/bad"
        ] do
      assert request(config, :get, path).status == 404
    end

    conn = request(config, :post, "/0/0/0.svg")
    assert conn.status == 405
    assert get_resp_header(conn, "allow") == ["GET, HEAD"]
    assert LiveMap.TestTileServer.request_count(server, "/0/0/0.mvt") == 0
  end

  test "returns 502 for upstream and decoding failures", %{server: server} do
    LiveMap.TestTileServer.put_responses(server, "/0/0/0.mvt", [
      {500, [], "failure"},
      {200, [], "not an mvt"}
    ])

    config = config(server)

    assert request(config, :get, "/0/0/0.svg").status == 502
    assert request(config, :get, "/0/0/0.svg").status == 502
    assert LiveMap.TestTileServer.request_count(server, "/0/0/0.mvt") == 2
  end

  test "validates initialization options", %{server: server} do
    assert_raise ArgumentError, ~r/source must be an MVT/, fn ->
      VectorTilePlug.init(source: %{url: "/tiles/{z}/{x}/{y}.svg"})
    end

    assert_raise ArgumentError, ~r/max_display_zoom must be a non-negative integer/, fn ->
      config(server, max_display_zoom: -1)
    end

    assert_raise ArgumentError, ~r/base-style must be one of/, fn ->
      config(server, base_style: "unknown")
    end

    assert_raise ArgumentError, ~r/compress must be a boolean/, fn ->
      config(server, compress: :sometimes)
    end
  end

  defp request(config, method, path) do
    method
    |> conn(path)
    |> VectorTilePlug.call(config)
  end

  defp config(server, opts \\ []) do
    source_max_zoom = Keyword.get(opts, :source_max_zoom, 14)

    defaults = [
      source: %{url: server.base_url <> "/{z}/{x}/{y}.mvt", max_zoom: source_max_zoom},
      max_age: 60
    ]

    VectorTilePlug.init(Keyword.merge(defaults, Keyword.delete(opts, :source_max_zoom)))
  end

  defp put_tile(server, path, count \\ 1) do
    responses = List.duplicate({200, [{"cache-control", "max-age=60"}], shortbread_tile()}, count)
    LiveMap.TestTileServer.put_responses(server, path, responses)
  end

  defp shortbread_tile do
    Path.expand("../fixtures/shortbread_fixture.mvt.base64", __DIR__)
    |> File.read!()
    |> String.replace(~r/\s+/, "")
    |> Base.decode64!()
  end
end
