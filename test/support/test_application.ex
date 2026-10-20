defmodule LiveMapTestApp do
  defmodule Application do
    def start do
      children = [
        LiveMapTestApp.Endpoint
      ]

      opts = [strategy: :one_for_one, name: LiveMapTestApp.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end

  defmodule Router do
    use Phoenix.Router
    import Phoenix.LiveView.Router

    scope "/" do
      live("/", LiveMap.View)
      live("/svg", LiveMapTestApp.SVGMap)
    end
  end

  # A map of SVG tiles, for the tests of the hook of the SVG tiles.
  defmodule SVGMap do
    use Phoenix.LiveView

    def mount(_params, _session, socket), do: {:ok, assign(socket, :zoom, 0)}

    def handle_event("zoom", %{"zoom" => zoom}, socket),
      do: {:noreply, assign(socket, :zoom, zoom)}

    def render(assigns) do
      ~H"""
      <.live_component
        module={LiveMap}
        id="live-map"
        width={256}
        height={256}
        zoom={@zoom}
        tile_source={%{url: "/vector/{z}/{x}/{y}.svg"}}
      />
      """
    end
  end

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :live_map

    plug(Plug.Parsers,
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Phoenix.json_library()
    )

    plug(Router)
  end
end
