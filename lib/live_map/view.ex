defmodule LiveMap.View do
  @moduledoc """
  A LiveView that displays a single LiveMap component.

  It can be used as an embeded map.
  """
  use Phoenix.LiveView

  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign_new(:width, fn -> params["width"] || 300 end)
     |> assign_new(:height, fn -> params["height"] || 150 end)
     |> assign_new(:center, fn ->
       params["center"] || {params["latitude"] || 0, params["longitude"] || 0}
     end)
     |> assign_new(:zoom, fn -> params["zoom"] || 0 end)}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={LiveMap} id="live-map"
      width={@width} height={@height}
      center={@center} zoom={@zoom}
    >
      <:zoom_in>+</:zoom_in>
      <:zoom_out>-</:zoom_out>
    </.live_component>
    """
  end
end
