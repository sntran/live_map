defmodule LiveMap.Coordinate do
  @moduledoc false

  @type pair :: {float(), float()}

  @spec parse_pair(term(), atom()) :: pair()
  def parse_pair(value, attribute) do
    case value do
      {latitude, longitude} ->
        pair(latitude, longitude, value, attribute)

      [latitude, longitude] ->
        pair(latitude, longitude, value, attribute)

      %{lat: latitude, lng: longitude} ->
        pair(latitude, longitude, value, attribute)

      %{"lat" => latitude, "lng" => longitude} ->
        pair(latitude, longitude, value, attribute)

      value when is_binary(value) ->
        parse_string_pair(value, attribute)

      _other ->
        invalid_pair!(value, attribute)
    end
  end

  @spec parse_number(term(), atom()) :: float()
  def parse_number(value, _attribute) when is_float(value), do: value
  def parse_number(value, _attribute) when is_integer(value), do: value / 1

  def parse_number(value, attribute) when is_binary(value) do
    case value |> String.trim() |> Float.parse() do
      {number, ""} -> number
      _error -> invalid_number!(value, attribute)
    end
  end

  def parse_number(value, attribute), do: invalid_number!(value, attribute)

  defp parse_string_pair(value, attribute) do
    case String.split(value, ",", parts: 2) do
      [latitude, longitude] -> pair(latitude, longitude, value, attribute)
      _other -> invalid_pair!(value, attribute)
    end
  end

  defp pair(latitude, longitude, value, attribute) do
    {
      parse_number(latitude, attribute),
      parse_number(longitude, attribute)
    }
  rescue
    ArgumentError -> invalid_pair!(value, attribute)
  end

  defp invalid_pair!(value, attribute) do
    raise ArgumentError,
          "invalid #{attribute}: expected \"latitude,longitude\", " <>
            "{latitude, longitude}, or %{lat: latitude, lng: longitude}; " <>
            "got: #{inspect(value)}"
  end

  defp invalid_number!(value, attribute) do
    raise ArgumentError, "invalid #{attribute} coordinate: #{inspect(value)}"
  end
end
