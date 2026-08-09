defmodule LiveMap.StyleTest do
  use ExUnit.Case, async: true
  alias LiveMap.Style

  test "to_css handles empty styles" do
    assert Style.to_css([]) == ""
    assert Style.to_css(nil) == ""
  end

  test "to_css processes visibility rules" do
    styles = [
      %{"featureType" => "all", "elementType" => "all", "stylers" => [%{"visibility" => "off"}]}
    ]

    css = Style.to_css(styles)

    assert css =~
             ".live-map-shortbread-feature:not(.live-map-shortbread-shape-text):not(.live-map-shortbread-shape-line) { display: none !important; }"

    assert css =~
             ".live-map-shortbread-feature.live-map-shortbread-shape-line { display: none !important; }"

    assert css =~
             ".live-map-shortbread-feature.live-map-shortbread-shape-text { display: none !important; }"
  end

  test "to_css lets elementType all re-enable default-hidden labels" do
    styles = [
      %{
        "featureType" => "poi",
        "elementType" => "all",
        "stylers" => [%{"visibility" => "simplified"}]
      }
    ]

    css = Style.to_css(styles)

    assert css =~
             ".live-map-shortbread-layer-pois.live-map-shortbread-shape-text, .live-map-shortbread-layer-public-transport.live-map-shortbread-shape-text { display: block !important; }"
  end

  test "to_css processes color and weight for geometry.stroke" do
    styles = [
      %{
        "featureType" => "road",
        "elementType" => "geometry.stroke",
        "stylers" => [%{"color" => "#ff0000"}, %{"weight" => 200}]
      }
    ]

    css = Style.to_css(styles)
    assert css =~ ".live-map-shortbread-role-street:not(.live-map-shortbread-shape-text)"
    assert css =~ "stroke: #ff0000 !important;"
    assert css =~ "stroke-width: 2.0px !important;"
  end

  test "to_css processes fill colors" do
    styles = [
      %{
        "featureType" => "water",
        "elementType" => "geometry.fill",
        "stylers" => [%{"color" => "#0000ff"}]
      }
    ]

    css = Style.to_css(styles)

    assert css =~
             ".live-map-shortbread-role-water:not(.live-map-shortbread-shape-text):not(.live-map-shortbread-shape-line)"

    assert css =~ "fill: #0000ff !important;"
  end

  test "to_css processes label styles" do
    styles = [
      %{
        "featureType" => "poi.park",
        "elementType" => "labels.text.fill",
        "stylers" => [%{"color" => "#00ff00"}]
      }
    ]

    css = Style.to_css(styles)

    assert css =~
             ".live-map-shortbread-role-land.live-map-shortbread-kind-park.live-map-shortbread-shape-text"

    assert css =~ "fill: #00ff00 !important;"
  end

  test "to_css covers all administrative and landscape feature selectors" do
    styles = [
      %{"featureType" => "administrative", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "administrative.country", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "administrative.land_parcel", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "administrative.locality", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "administrative.neighborhood", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "administrative.province", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "landscape", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "landscape.man_made", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "landscape.natural", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "landscape.natural.landcover", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "landscape.natural.terrain", "stylers" => [%{"visibility" => "on"}]}
    ]

    css = Style.to_css(styles)
    assert css =~ "live-map-shortbread-role-boundary"
    assert css =~ "live-map-shortbread-admin-level-2"
    assert css =~ "live-map-shortbread-admin-level-4"
    assert css =~ "live-map-shortbread-layer-place-labels"
    assert css =~ "live-map-shortbread-role-land"
  end

  test "to_css covers all poi feature selectors" do
    styles = [
      %{"featureType" => "poi", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "poi.attraction", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "poi.business", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "poi.government", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "poi.medical", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "poi.park", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "poi.place_of_worship", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "poi.school", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "poi.sports_complex", "stylers" => [%{"visibility" => "on"}]}
    ]

    css = Style.to_css(styles)
    assert css =~ "live-map-shortbread-layer-pois"
    assert css =~ "live-map-shortbread-layer-public-transport"
    assert css =~ "live-map-shortbread-kind-school"
  end

  test "to_css covers road and transit feature selectors" do
    styles = [
      %{"featureType" => "road", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "road.arterial", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "road.highway", "stylers" => [%{"visibility" => "on"}]},
      %{
        "featureType" => "road.highway.controlled_access",
        "stylers" => [%{"visibility" => "on"}]
      },
      %{"featureType" => "road.local", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "transit", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "transit.line", "stylers" => [%{"visibility" => "on"}]},
      %{"featureType" => "transit.station", "stylers" => [%{"visibility" => "on"}]}
    ]

    css = Style.to_css(styles)
    assert css =~ "live-map-shortbread-role-street"
    assert css =~ "live-map-shortbread-layer-public-transport"
  end

  test "to_css handles string weight" do
    styles = [
      %{
        "featureType" => "road",
        "elementType" => "geometry.stroke",
        "stylers" => [%{"weight" => "150"}]
      }
    ]

    assert Style.to_css(styles) =~ "stroke-width: 1.5px !important;"

    styles2 = [
      %{
        "featureType" => "road",
        "elementType" => "geometry.stroke",
        "stylers" => [%{"weight" => "invalid"}]
      }
    ]

    css2 = Style.to_css(styles2)
    refute css2 =~ "stroke-width"
  end

  test "to_css handles other elementTypes with color" do
    styles = [
      %{
        "featureType" => "all",
        "elementType" => "labels.text.stroke",
        "stylers" => [%{"color" => "#333"}]
      },
      %{"featureType" => "all", "elementType" => "labels", "stylers" => [%{"color" => "#111"}]},
      %{"featureType" => "all", "elementType" => "all", "stylers" => [%{"color" => "#000"}]}
    ]

    css = Style.to_css(styles)
    assert css =~ "stroke: #333 !important;"
    assert css =~ "fill: #111 !important;"
    assert css =~ "fill: #000 !important;"
  end

  test "to_css ignores unsupported stylers" do
    assert Style.to_css([%{"stylers" => [%{"saturation" => -100}]}]) == ""
  end
end
