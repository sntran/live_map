defmodule LiveMap.Component do
  @moduledoc """
  A Phoenix LiveView component that can be used to display an interactive
  vector map with dynamic data.

  A LiveMap can be added to a LiveView by:

  ```heex
  <.live_component module={LiveMap}
    id="live-map"
    width="800"
    height="600"
    title="Awesome Live Map"
  >
  </.live_component>
  ```
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
