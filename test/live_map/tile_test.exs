defmodule LiveMap.TileTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import Bitwise, only: [<<<: 2]

  alias LiveMap.Tile
  doctest Tile

  test "provides built-in raster, vector, and physical sources" do
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

    assert Tile.default_physical_source() === %{
             type: :raster,
             url:
               "https://server.arcgisonline.com/ArcGIS/rest/services/World_Physical_Map/MapServer/tile/{z}/{y}/{x}",
             version: nil,
             max_zoom: 8,
             headers: [],
             attribution:
               "Physical map: U.S. National Park Service · Map data © OpenStreetMap contributors",
             attribution_url: "https://goto.arcgisonline.com/maps/World_Physical_Map"
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

  test "prepare_layer crops overzoomed raster source tiles" do
    layer =
      Tile.prepare_layer(
        [%{x: 10, y: 13, z: 5}],
        %{url: "https://tiles.example.com/{z}/{x}/{y}.jpg", max_zoom: 3}
      )

    assert layer.tiles === [
             %{
               type: :image,
               x: 2560,
               y: 3328,
               width: 256,
               height: 256,
               href: "https://tiles.example.com/3/2/3.jpg",
               view_box: "128 64 64 64"
             }
           ]
  end

  test "prepare_layer preserves source attribution metadata" do
    layer =
      Tile.prepare_layer([], %{
        "url" => "https://tiles.example.com/{z}/{x}/{y}.jpg",
        "attribution" => "Example tiles",
        "attribution_url" => "https://tiles.example.com/terms"
      })

    assert layer.source.attribution == "Example tiles"
    assert layer.source.attribution_url == "https://tiles.example.com/terms"
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
       ~r/invalid tile source header/},
      {%{url: "https://tiles.example.com/{z}/{x}/{y}.png", attribution: ""},
       ~r/source.attribution must be a non-empty string/},
      {%{
         url: "https://tiles.example.com/{z}/{x}/{y}.png",
         attribution_url: "/terms"
       }, ~r/source.attribution_url must be an absolute http\(s\) URL/}
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

    test "retains decoded tiles after they leave the viewport" do
      existing_layer = ready_vector_layer(1, 0, 0)
      source = %{type: :mvt, url: "http://example.com/{z}/{x}/{y}.mvt"}

      panned_layer = Tile.prepare_layer([%{z: 1, x: 1, y: 0}], source, existing_layer)
      returned_layer = Tile.prepare_layer([%{z: 1, x: 0, y: 0}], source, panned_layer)

      assert panned_layer.cached_tiles["1/0/0"].state == "ready"

      assert [%{state: "ready", display_tile: "1/0/0", def_id: "test"}] =
               returned_layer.tiles

      assert returned_layer.defs == existing_layer.defs
    end

    test "uses the nearest cached parent while a child tile loads" do
      existing_layer = ready_vector_layer(1, 0, 0)
      source = %{type: :mvt, url: "http://example.com/{z}/{x}/{y}.mvt"}

      result = Tile.prepare_layer([%{z: 2, x: 1, y: 1}], source, existing_layer)

      assert [tile] = result.tiles
      assert tile.state == "loading"
      assert tile.placeholder
      assert tile.fallback_tile == "1/0/0"
      assert tile.def_id == "test"
      assert IO.iodata_to_binary(tile.view_box) == "0.5 0.5 0.5 0.5"
      assert result.defs == existing_layer.defs
    end

    test "composes a cached overzoom crop into the child placeholder" do
      existing_layer = ready_vector_layer(15, 1, 0, "0.5 0 0.5 0.5")
      source = %{type: :mvt, url: "http://example.com/{z}/{x}/{y}.mvt", max_zoom: 14}

      result = Tile.prepare_layer([%{z: 16, x: 3, y: 1}], source, existing_layer)

      assert [tile] = result.tiles
      assert tile.fallback_tile == "15/1/0"
      assert IO.iodata_to_binary(tile.view_box) == "0.75 0.25 0.25 0.25"
    end

    test "finds cached parents across the wrapped negative x range" do
      existing_layer = ready_vector_layer(1, -1, 0)
      source = %{type: :mvt, url: "http://example.com/{z}/{x}/{y}.mvt"}

      result = Tile.prepare_layer([%{z: 2, x: -1, y: 0}], source, existing_layer)

      assert [%{placeholder: true, fallback_tile: "1/-1/0"}] = result.tiles
    end
  end

  defp ready_vector_layer(z, x, y, view_box \\ "0 0 1 1") do
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
          view_box: view_box,
          source_tile: "#{z}/#{x}/#{y}"
        }
      ]
    }
  end
end
