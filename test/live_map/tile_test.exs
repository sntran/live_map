defmodule LiveMap.TileTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import Bitwise, only: [<<<: 2]

  alias LiveMap.Tile
  doctest Tile

  test "provides built-in raster and vector sources" do
    assert Tile.default_source() === %{
             type: :raster,
             url: "https://tile.openstreetmap.org/{zoom}/{x}/{y}.png",
             version: nil,
             max_zoom: nil,
             headers: []
           }

    assert Tile.default_vector_source() === %{
             type: :mvt,
             url: "https://vector.openstreetmap.org/$VERSION/{zoom}/{x}/{y}.mvt",
             version: "shortbread_v1",
             max_zoom: 14,
             headers: []
           }
  end

  property "conversion between x and longitude" do
    check all(
            zoom <- StreamData.integer(0..18),
            x <- StreamData.integer(0..((1 <<< zoom) - 1)),
            longitude = Tile.longitude(x, zoom)
          ) do
      assert round(Tile.x(longitude, zoom)) === x
    end
  end

  property "conversion between y and latitude" do
    check all(
            zoom <- StreamData.integer(0..18),
            y <- StreamData.integer(0..((1 <<< zoom) - 1)),
            latitude = Tile.latitude(y, zoom)
          ) do
      assert round(Tile.y(latitude, zoom)) === y
    end
  end

  test "prepare_layer infers raster sources and expands URLs" do
    layer =
      Tile.prepare_layer(
        [%{x: 0, y: 0, z: 2}],
        %{url: "https://tiles.example.com/{z}/{x}/{y}.png?zoom={zoom}"}
      )

    assert layer.source.type === :raster
    assert layer.source.version === nil

    assert layer.tiles === [
             %{
               type: :image,
               x: 0,
               y: 0,
               width: 256,
               height: 256,
               href: "https://tiles.example.com/2/0/0.png?zoom=2"
             }
           ]
  end

  test "prepare_layer only requires versions for versioned templates" do
    layer =
      Tile.prepare_layer([%{x: 0, y: 0, z: 0}], %{
        url: "https://tiles.example.com/{z}/{x}/{y}.png"
      })

    assert layer.source.version === nil

    assert_raise ArgumentError, ~r/source.version is required/, fn ->
      Tile.prepare_layer([%{x: 0, y: 0, z: 0}], %{
        url: "https://vector.example.com/$VERSION/{z}/{x}/{y}.mvt"
      })
    end
  end

  test "prepare_layer uses defaults for nil and empty vector sources" do
    raster_layer = Tile.prepare_layer([], nil)
    vector_layer = Tile.prepare_layer([], %{url: "https://vector.example.com/{z}/{x}/{y}.mvt"})

    assert raster_layer.source === Tile.default_source()
    assert raster_layer.defs === []
    assert raster_layer.tiles === []

    assert vector_layer.source.type === :mvt
    assert vector_layer.source.max_zoom === 14
    assert vector_layer.defs === []
    assert vector_layer.tiles === []
  end

  test "prepare_layer normalizes string-keyed vector sources" do
    layer =
      Tile.prepare_layer([], %{
        "url" => "https://vector.example.com/$VERSION/{z}/{x}/{y}.pbf",
        "version" => "shortbread_v1",
        "max_zoom" => 8,
        "headers" => [%{name: "x-example", value: "demo"}]
      })

    assert layer.source === %{
             type: :mvt,
             url: "https://vector.example.com/$VERSION/{z}/{x}/{y}.pbf",
             version: "shortbread_v1",
             max_zoom: 8,
             headers: [{"x-example", "demo"}]
           }
  end

  test "prepare_layer accepts string source types and expands dollar version placeholders" do
    raster_layer =
      Tile.prepare_layer(
        [%{x: 1, y: 2, z: 3}],
        %{
          type: "raster",
          url: "https://tiles.example.com/$VERSION/{z}/{x}/{y}.png",
          version: "v1"
        }
      )

    vector_layer =
      Tile.prepare_layer([], %{type: "mvt", url: "https://vector.example.com/{z}/{x}/{y}.mvt"})

    assert hd(raster_layer.tiles).href === "https://tiles.example.com/v1/3/1/2.png"
    assert vector_layer.source.type === :mvt
  end

  test "prepare_layer validates source configuration" do
    cases = [
      {%{}, ~r/source.url is required/},
      {%{url: 123}, ~r/source.url must be a non-empty string/},
      {%{url: "ftp://tiles.example.com/{z}/{x}/{y}.png"},
       ~r/source.url must be an absolute http\(s\) URL/},
      {%{url: "/{z}/{x}/{y}.png"}, ~r/source.url must be an absolute http\(s\) URL/},
      {%{url: "https://tiles.example.com/{x}/{y}.png"},
       ~r/source.url must include a zoom placeholder/},
      {%{url: "https://tiles.example.com/{z}/{y}.png"},
       ~r/source.url must include an x placeholder/},
      {%{url: "https://tiles.example.com/{z}/{x}.png"},
       ~r/source.url must include a y placeholder/},
      {%{url: "https://tiles.example.com/{z}/{x}/{y}.png", type: :vector},
       ~r/unsupported source type/},
      {%{url: "https://tiles.example.com/$VERSION/{z}/{x}/{y}.mvt", version: ""},
       ~r/source.version must be a non-empty string/},
      {%{url: "https://tiles.example.com/{z}/{x}/{y}.mvt", max_zoom: -1},
       ~r/source.max_zoom must be a non-negative integer/},
      {%{url: "https://tiles.example.com/{z}/{x}/{y}.png", headers: "invalid"},
       ~r/source.headers must be a list/},
      {%{url: "https://tiles.example.com/{z}/{x}/{y}.png", headers: [%{name: "x-example"}]},
       ~r/invalid tile source header/}
    ]

    Enum.each(cases, fn {source, message} ->
      assert_raise ArgumentError, message, fn ->
        Tile.prepare_layer([], source)
      end
    end)
  end

  describe "fetch_vector_layer/4" do
    test "delegates raster sources to regular layer preparation" do
      result =
        Tile.fetch_vector_layer(
          [%{x: 1, y: 2, z: 3}],
          %{type: :raster, url: "https://tiles.example.com/{z}/{x}/{y}.png"},
          ""
        )

      assert [%{type: :image, href: "https://tiles.example.com/3/1/2.png"}] = result.tiles
    end

    test "merges existing_layer tiles" do
      existing_layer = ready_vector_layer(0, 0, 0)
      source = %{type: :mvt, url: "http://example.com/{z}/{x}/{y}.mvt"}
      tiles = [LiveMap.Tile.at(0, 0, 0)]

      result = LiveMap.Tile.fetch_vector_layer(tiles, source, "", existing_layer)
      assert length(result.tiles) == 1
      assert hd(result.tiles).state == "ready"
    end

    test "prepares overzoomed source coordinates while loading" do
      source = %{type: :mvt, url: "http://example.com/{z}/{x}/{y}.mvt", max_zoom: 1}
      tiles = [LiveMap.Tile.at(0, 0, 2)]

      result = LiveMap.Tile.prepare_layer(tiles, source)

      assert length(result.tiles) == 1
      tile = hd(result.tiles)
      assert tile.state == "loading"
      assert tile.display_tile == "2/2/2"
      assert tile.source_tile == "1/1/1"
    end
  end

  test "stream_vector_layer rejects raster sources" do
    source = %{type: :raster, url: "https://tiles.example.com/{z}/{x}/{y}.png"}

    assert_raise ArgumentError, ~r/requires an MVT tile source/, fn ->
      Tile.stream_vector_layer([], source, "", %{defs: [], tiles: []}, fn _delta -> :ok end)
    end
  end

  describe "prepare_layer/3" do
    test "preserves ready existing layer tiles" do
      existing_layer = ready_vector_layer(0, 0, 0)
      source = %{type: :mvt, url: "http://example.com/{z}/{x}/{y}.mvt"}
      tiles = [LiveMap.Tile.at(0, 0, 0)]

      result = LiveMap.Tile.prepare_layer(tiles, source, existing_layer)
      assert length(result.tiles) == 1
      assert hd(result.tiles).state == "ready"
      assert result.defs == existing_layer.defs
    end

    test "does not reuse the same x/y coordinates from another zoom" do
      existing_layer = ready_vector_layer(3, 2, 2)
      source = %{type: :mvt, url: "http://example.com/{z}/{x}/{y}.mvt"}

      result = Tile.prepare_layer([%{z: 2, x: 2, y: 2}], source, existing_layer)

      assert [%{state: "loading", display_tile: "2/2/2", source_tile: "2/2/2"}] =
               result.tiles

      assert result.defs == []
    end
  end

  defp ready_vector_layer(z, x, y) do
    %{
      defs: [Phoenix.HTML.raw("<svg id=\"test\"></svg>")],
      tiles: [
        %{
          type: :svg_use,
          state: "ready",
          display_tile: "#{z}/#{x}/#{y}",
          z: z,
          x: x * 256,
          y: y * 256,
          width: 256,
          height: 256,
          def_id: "test",
          view_box: "0 0 1 1",
          source_tile: "#{z}/#{x}/#{y}"
        }
      ]
    }
  end
end
