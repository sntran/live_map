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
      <:map_control action="pan-up">↑</:map_control>
      <:map_control action="pan-left">←</:map_control>
      <:map_control action="pan-right">→</:map_control>
      <:map_control action="pan-down">↓</:map_control>
      <:map_control action="zoom-in">+</:map_control>
      <:map_control action="zoom-out">-</:map_control>
      <:map_control action="fullscreen">⛶</:map_control>
    </.live_component>
    """
  end
end
