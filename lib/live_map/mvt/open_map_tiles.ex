defmodule LiveMap.MVT.OpenMapTiles do
  @moduledoc false
  # The features of a tile of the OpenMapTiles schema (as OpenFreeMap
  # serves it) as features of the Shortbread schema, so the CSS and the
  # styles of LiveMap draw them. A feature that LiveMap does not draw (a
  # point of interest, a house number, the name of a road) goes.

  @doc """
  The Shortbread features of an OpenMapTiles feature: none, or one.
  """
  @spec normalize(map()) :: [map()]
  def normalize(%{layer: layer, properties: properties} = feature) do
    case shortbread(layer, feature.type, properties) do
      nil -> []
      # A label with no name.
      {_layer, %{"name" => nil}} -> []
      {new_layer, new_properties} -> [%{feature | layer: new_layer, properties: new_properties}]
    end
  end

  defp shortbread("water", :polygon, %{"class" => "ocean"} = properties),
    do: {"ocean", base("water", properties)}

  defp shortbread("water", :polygon, properties),
    do: {"water_polygons", base("water", properties)}

  defp shortbread("waterway", :line, properties),
    do: {"water_lines", base(properties["class"], properties)}

  defp shortbread("landcover", :polygon, properties),
    do: {"land", %{"kind" => landcover(properties["class"], properties["subclass"])}}

  defp shortbread("landuse", :polygon, properties),
    do: {"land", %{"kind" => properties["class"] || "default"}}

  defp shortbread("park", :polygon, _properties), do: {"land", %{"kind" => "park"}}

  defp shortbread("transportation", :line, %{"class" => "ferry"}),
    do: {"ferries", %{"kind" => "ferry"}}

  defp shortbread("transportation", :line, %{"class" => class})
       when class in ["aerialway", "cable_car", "gondola"],
       do: {"aerialways", %{"kind" => class}}

  defp shortbread("transportation", :line, %{"class" => class} = properties),
    do: {"streets", base(street(class, properties["subclass"]), properties)}

  defp shortbread("transportation", :polygon, %{"class" => "pier"}),
    do: {"pier_polygons", %{"kind" => "pier"}}

  defp shortbread("building", :polygon, _properties), do: {"buildings", %{"kind" => "building"}}

  defp shortbread("boundary", :line, %{"maritime" => maritime}) when maritime in [1, true],
    do: nil

  # The borders of the countries and of the provinces only, as in
  # Shortbread.
  defp shortbread("boundary", :line, %{"admin_level" => level} = properties)
       when level in [2, 4],
       do:
         {"boundaries",
          %{
            "kind" =>
              if(properties["disputed"] in [1, true], do: "disputed", else: "administrative"),
            "admin_level" => level
          }}

  defp shortbread("aeroway", :polygon, %{"class" => class}) when class in ["runway", "taxiway"],
    do: {"street_polygons", %{"kind" => class}}

  defp shortbread("place", :point, %{"class" => class} = properties)
       when class in ["country", "state", "province"] do
    {"boundary_labels",
     %{
       "kind" => "administrative",
       "admin_level" => if(class == "country", do: 2, else: 4),
       "name" => name(properties),
       "way_area" => area(properties["rank"])
     }}
  end

  defp shortbread("place", :point, %{"class" => class} = properties) do
    {"place_labels",
     %{
       "kind" => place(class, properties["capital"]),
       "name" => name(properties),
       "population" => population(class, properties["rank"])
     }}
  end

  defp shortbread("water_name", :point, properties),
    do:
      {"water_polygons_labels",
       %{"kind" => properties["class"] || "water", "name" => name(properties)}}

  defp shortbread(_layer, _type, _properties), do: nil

  # The kind of a feature, and its bridge or tunnel (`brunnel`).
  defp base(kind, properties) do
    %{
      "kind" => kind || "default",
      "bridge" => properties["brunnel"] == "bridge",
      "tunnel" => properties["brunnel"] == "tunnel"
    }
  end

  defp landcover("wood", _subclass), do: "forest"
  defp landcover("sand", "beach"), do: "beach"
  defp landcover(class, _subclass), do: class || "default"

  # The small roads are "unclassified" in Shortbread; a railway, a path
  # and a service road keep the kind of their subclass.
  defp street("minor", _subclass), do: "unclassified"
  defp street("transit", subclass), do: subclass || "subway"
  defp street(class, subclass) when class in ["rail", "path", "service"], do: subclass || class
  defp street(class, _subclass), do: class

  defp place(_class, 2), do: "capital"
  defp place(_class, 4), do: "state_capital"
  defp place("isolated_dwelling", _capital), do: "locality"
  defp place(class, _capital), do: class

  # The Latin name first, as the maps of MapLibre.
  defp name(properties), do: properties["name:latin"] || properties["name"]

  # OpenMapTiles has a rank of the places (1 first), and no population:
  # the main cities get the priority of a large population.
  defp population("city", rank) when is_integer(rank) and rank <= 3, do: 1_000_000
  defp population("city", _rank), do: 250_000
  defp population("town", _rank), do: 50_000
  defp population(_class, _rank), do: 0

  defp area(rank) when is_integer(rank) and rank <= 2, do: 100_000_000_000
  defp area(rank) when is_integer(rank) and rank <= 4, do: 25_000_000_000
  defp area(_rank), do: 5_000_000_000
end
