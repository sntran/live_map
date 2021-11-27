defmodule LiveMapsWeb.PageLive do
  use LiveMapsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:latitude, 10.4197639)
     |> assign(:longitude, 107.1070841)
     |> assign(:zoom, 11)
    }
  end

  @impl true
  def handle_event("change", %{"latitude" => latitude, "longitude" => longitude, "zoom" => zoom}, socket) do
    {latitude, _} = Float.parse(latitude)
    {longitude, _} = Float.parse(longitude)
    {zoom, _} = Integer.parse(zoom)

    {:noreply,
     socket
     |> assign(:latitude, latitude)
     |> assign(:longitude, longitude)
     |> assign(:zoom, zoom)
    }
  end
end
