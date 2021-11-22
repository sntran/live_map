defmodule LiveMap do
  @external_resource "./README.md"
  @moduledoc """
  #{File.read!(@external_resource)}
  """

  use Phoenix.LiveComponent

  @impl Phoenix.LiveComponent
  @spec mount(Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:width, fn -> 300 end)
     |> assign_new(:height, fn -> 150 end)
     |> assign_new(:title, fn -> "" end)
    }
  end

  # @callback render/1 is handled by `Phoenix.LiveView.Renderer.before_compile`
  # by looking for a ".html" file with the same name as this module.
end
