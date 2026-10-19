# The fixtures

| File | Content | Source |
|---|---|---|
| `shortbread_fixture.mvt.base64` | One small MVT tile in the schema of Shortbread. | Made for the tests. |
| `protomaps_ha_giang.pmtiles` | A PMTiles archive (version 3) of 7 tiles of the town of Hà Giang, zoom 12 to 14, in the schema of the Protomaps basemap (version 4). | `pmtiles extract https://build.protomaps.com/20261019.pmtiles protomaps_ha_giang.pmtiles --bbox=104.970,22.815,104.995,22.835 --minzoom=12 --maxzoom=14` (go-pmtiles 1.31.2). |
| `protomaps_ha_giang.json` | The SHA-256 of the data of each tile of `protomaps_ha_giang.pmtiles`, after the decompression, from go-pmtiles 1.31.2. | Made with go-pmtiles. |

The data of `protomaps_ha_giang.pmtiles` is © OpenStreetMap contributors,
under the Open Database License (ODbL 1.0,
https://www.openstreetmap.org/copyright). The build is from Protomaps
(https://protomaps.com).
