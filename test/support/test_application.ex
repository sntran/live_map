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
