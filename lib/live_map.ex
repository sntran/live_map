defmodule LiveMap do
  @external_resource "./README.md"
  @moduledoc """
  #{File.read!(@external_resource)}
  """

  @doc """
  Hello world.

  ## Examples

      iex> LiveMap.hello()
      :world

  """
  def hello do
    :world
  end
end
