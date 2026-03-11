Mix.install([
  {:phoenix, "~> 1.8"},
  {:phoenix_html, "~> 4.3"},
  {:phoenix_live_view, "~> 1.1"},
  {:plug_cowboy, "~> 2.8"},
  {:jason, "~> 1.4"},
  {:live_map, path: Path.expand("..", __DIR__)}
])

Application.put_env(:phoenix, :json_library, Jason)

defmodule LiveMapExample.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full w-full bg-white">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>LiveMap Demo</title>
        <script src="https://cdn.tailwindcss.com?plugins=forms"></script>
      </head>
      <body class="m-0 h-full w-full overflow-hidden bg-slate-950 text-slate-950 antialiased">
        {@inner_content}

        <script type="module">
          import {Socket} from "https://esm.sh/phoenix@1.8.1"
          import {LiveSocket} from "https://esm.sh/phoenix_live_view@1.1.27"

          const Hooks = {}

          Hooks.MapViewport = {
            mounted() {
              this.drag = null
              this.zoomLocked = false
              this.zoomUnlockTimer = null
              this.lastPanAt = 0
              this.panInterval = 80

              this.onPointerDown = (event) => {
                if (
                  event.button !== 0 ||
                    this.zoomControlTarget(event.target) ||
                    this.interactiveTarget(event.target)
                ) {
                  return
                }

                this.drag = {
                  pointerId: event.pointerId,
                  x: event.clientX,
                  y: event.clientY,
                  pendingX: 0,
                  pendingY: 0
                }

                this.el.setPointerCapture(event.pointerId)
                this.el.classList.remove("cursor-grab")
                this.el.classList.add("cursor-grabbing")
                event.preventDefault()
              }

              this.onPointerMove = (event) => {
                if (!this.drag || this.drag.pointerId !== event.pointerId) {
                  return
                }

                this.drag.pendingX += event.clientX - this.drag.x
                this.drag.pendingY += event.clientY - this.drag.y
                this.drag.x = event.clientX
                this.drag.y = event.clientY

                if (Date.now() - this.lastPanAt >= this.panInterval) {
                  this.flushPan()
                }
              }

              this.onPointerUp = (event) => {
                if (!this.drag || this.drag.pointerId !== event.pointerId) {
                  return
                }

                this.flushPan()
                this.releaseDrag(event.pointerId)
              }

              this.onLostPointerCapture = () => {
                this.releaseDrag()
              }

              this.onWheel = (event) => {
                if (this.interactiveTarget(event.target)) {
                  return
                }

                if (this.zoomLocked || !Number.isFinite(event.deltaY) || event.deltaY === 0) {
                  if (event.deltaY !== 0) {
                    event.preventDefault()
                  }

                  return
                }

                event.preventDefault()
                this.zoomLocked = true
                this.pushZoomAt(event, event.deltaY < 0 ? 1 : -1)

                clearTimeout(this.zoomUnlockTimer)
                this.zoomUnlockTimer = setTimeout(() => {
                  this.zoomLocked = false
                }, 120)
              }

              this.onZoomClick = (event) => {
                const target = this.zoomControlTarget(event.target)

                if (!target) {
                  return
                }

                event.preventDefault()
                event.stopPropagation()
                this.pushEvent("adjust_zoom", {delta: this.zoomDirection(target)})
              }

              this.onZoomKey = (event) => {
                const target = this.zoomControlTarget(event.target)

                if (!target || !["Enter", " ", "Spacebar"].includes(event.key)) {
                  return
                }

                event.preventDefault()
                event.stopPropagation()
                this.pushEvent("adjust_zoom", {delta: this.zoomDirection(target)})
              }

              this.onDoubleClick = (event) => {
                if (this.zoomControlTarget(event.target) || this.interactiveTarget(event.target)) {
                  return
                }

                event.preventDefault()
                this.pushZoomAt(event, event.shiftKey ? -1 : 1)
              }

              this.el.addEventListener("pointerdown", this.onPointerDown)
              this.el.addEventListener("pointermove", this.onPointerMove)
              this.el.addEventListener("pointerup", this.onPointerUp)
              this.el.addEventListener("pointercancel", this.onPointerUp)
              this.el.addEventListener("lostpointercapture", this.onLostPointerCapture)
              this.el.addEventListener("wheel", this.onWheel, {passive: false})
              this.el.addEventListener("dblclick", this.onDoubleClick)
              this.el.addEventListener("click", this.onZoomClick, true)
              this.el.addEventListener("keyup", this.onZoomKey, true)
            },

            destroyed() {
              clearTimeout(this.zoomUnlockTimer)
              this.el.removeEventListener("pointerdown", this.onPointerDown)
              this.el.removeEventListener("pointermove", this.onPointerMove)
              this.el.removeEventListener("pointerup", this.onPointerUp)
              this.el.removeEventListener("pointercancel", this.onPointerUp)
              this.el.removeEventListener("lostpointercapture", this.onLostPointerCapture)
              this.el.removeEventListener("wheel", this.onWheel)
              this.el.removeEventListener("dblclick", this.onDoubleClick)
              this.el.removeEventListener("click", this.onZoomClick, true)
              this.el.removeEventListener("keyup", this.onZoomKey, true)
            },

            flushPan() {
              if (!this.drag || (this.drag.pendingX === 0 && this.drag.pendingY === 0)) {
                return
              }

              const surface = this.el.querySelector("#live-map")
              const rect = surface?.getBoundingClientRect()

              if (!rect || rect.width === 0 || rect.height === 0) {
                return
              }

              this.pushEvent("pan", {
                dx: this.drag.pendingX.toFixed(2),
                dy: this.drag.pendingY.toFixed(2),
                display_width: rect.width.toFixed(2),
                display_height: rect.height.toFixed(2)
              })

              this.drag.pendingX = 0
              this.drag.pendingY = 0
              this.lastPanAt = Date.now()
            },

            releaseDrag(pointerId) {
              if (pointerId && this.el.hasPointerCapture(pointerId)) {
                this.el.releasePointerCapture(pointerId)
              }

              this.drag = null
              this.el.classList.remove("cursor-grabbing")
              this.el.classList.add("cursor-grab")
            },

            zoomControlTarget(target) {
              return target?.closest?.('[aria-label="Zoom In"], [aria-label="Zoom Out"]')
            },

            interactiveTarget(target) {
              return target?.closest?.('[data-map-interactive="true"]')
            },

            zoomDirection(target) {
              return target?.getAttribute("aria-label") === "Zoom In" ? 1 : -1
            },

            pushZoomAt(event, delta) {
              const surface = this.el.querySelector("#live-map")
              const rect = surface?.getBoundingClientRect()

              if (!rect || rect.width === 0 || rect.height === 0) {
                this.pushEvent("adjust_zoom", {delta})
                return
              }

              this.pushEvent("zoom_at", {
                delta,
                x: (event.clientX - rect.left).toFixed(2),
                y: (event.clientY - rect.top).toFixed(2),
                display_width: rect.width.toFixed(2),
                display_height: rect.height.toFixed(2)
              })
            }
          }

          const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
          const liveSocket = new LiveSocket("/live", Socket, {
            hooks: Hooks,
            params: {_csrf_token: csrfToken}
          })

          liveSocket.connect()
          window.liveSocket = liveSocket
        </script>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <main class="h-screen w-screen overflow-hidden">
      {@inner_content}
    </main>
    """
  end
end

defmodule LiveMapExample.PageLive do
  use Phoenix.LiveView, layout: {LiveMapExample.Layouts, :app}

  @map_width 1600
  @map_height 900
  @max_zoom 18
  @mercator_limit 85.0511287798066
  @markers [
    %{
      id: "harbor",
      icon: "A",
      label: "Harbor",
      latitude: 10.411379,
      longitude: 107.136224
    },
    %{
      id: "front-beach",
      icon: "B",
      label: "Front Beach",
      latitude: 10.33686,
      longitude: 107.08479
    },
    %{
      id: "back-beach",
      icon: "W",
      label: "Back Beach",
      latitude: 10.33454,
      longitude: 107.09652
    },
    %{
      id: "lighthouse",
      icon: "L",
      label: "Vung Tau Lighthouse",
      latitude: 10.34618,
      longitude: 107.0843
    },
    %{
      id: "jesus",
      icon: "M",
      label: "Christ of Vung Tau",
      latitude: 10.34138,
      longitude: 107.09304
    },
    %{
      id: "long-son",
      icon: "I",
      label: "Long Son",
      latitude: 10.48823,
      longitude: 107.0086
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:map_width, @map_width)
     |> assign(:map_height, @map_height)
      |> assign(:markers, @markers)
     |> assign(:latitude, 10.4197639)
     |> assign(:longitude, 107.1070841)
     |> assign(:zoom, 11)}
  end

  @impl true
  def handle_event("adjust_zoom", %{"delta" => delta}, socket) do
    {:noreply,
     assign_view(socket, %{
       latitude: socket.assigns.latitude,
       longitude: socket.assigns.longitude,
       zoom: socket.assigns.zoom + parse_integer(delta, 0)
     })}
  end

  @impl true
  def handle_event("zoom_at", params, socket) do
    {:noreply, assign_view(socket, zoom_at(socket.assigns, params))}
  end

  @impl true
  def handle_event("pan", params, socket) do
    {:noreply, assign_view(socket, pan_view(socket.assigns, params))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="absolute inset-0 overflow-hidden bg-slate-200">
      <div class="pointer-events-none absolute inset-x-0 top-0 z-10 p-3 sm:p-4">
        <div class="pointer-events-auto flex items-start justify-end">
          <div class="flex justify-end sm:pt-1">
            <button
              type="button"
              command="show-popover"
              commandfor="map-help"
              class="inline-flex h-10 w-10 items-center justify-center rounded-full border border-slate-300 bg-white text-slate-700 shadow-sm transition hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-600"
            >
              <span aria-hidden="true" class="text-lg font-semibold leading-none">i</span>
              <span class="sr-only">Show map interaction instructions</span>
            </button>
          </div>
        </div>
      </div>

      <div class="absolute right-3 top-[5.5rem] z-20 sm:right-4 sm:top-[5.75rem]">
        <div
          id="map-help"
          popover
          class="max-w-sm rounded-2xl border border-slate-300 bg-white p-4 text-sm leading-7 text-slate-700 shadow-lg backdrop:bg-slate-950/20"
        >
          Drag to pan, use the mouse wheel to zoom, click markers to open popovers, and inspect the live center marker for the current coordinates and zoom.
        </div>
      </div>

      <div class="pointer-events-none absolute inset-x-0 top-0 h-28 bg-gradient-to-b from-slate-200/70 to-transparent"></div>

      <div
        id="map-viewport"
        phx-hook="MapViewport"
        data-latitude={@latitude}
        data-longitude={@longitude}
        data-zoom={@zoom}
        class="relative h-full w-full cursor-grab touch-none overflow-hidden bg-white"
      >
        <.live_component
          module={LiveMap}
          id="live-map"
          class="block h-full w-full"
          title="Example Live Map"
          width={@map_width}
          height={@map_height}
          latitude={@latitude}
          longitude={@longitude}
          zoom={@zoom}
        >
          <:marker
            :for={marker <- @markers}
            id={marker.id}
            latitude={marker.latitude}
            longitude={marker.longitude}
            label={marker.label}
          >
            <.place_marker marker={marker} />
          </:marker>

          <:marker
            id="map-center"
            latitude={@latitude}
            longitude={@longitude}
            label="Map center"
          >
            <.center_marker latitude={@latitude} longitude={@longitude} zoom={@zoom} />
          </:marker>

          <:zoom_in>
            <span
              class="flex h-6 w-6 items-center justify-center rounded-md bg-white/95 text-base font-black text-slate-900"
              aria-hidden="true"
            >
              +
            </span>
          </:zoom_in>

          <:zoom_out>
            <span
              class="flex h-6 w-6 items-center justify-center rounded-md bg-white/95 text-lg font-black leading-none text-slate-900"
              aria-hidden="true"
            >
              -
            </span>
          </:zoom_out>

        </.live_component>
      </div>
    </section>
    """
  end

  defp assign_view(socket, params) do
    assign(socket,
      latitude: params[:latitude] |> clamp_latitude() |> round_coordinate(),
      longitude: params[:longitude] |> normalize_longitude() |> round_coordinate(),
      zoom: params[:zoom] |> clamp_zoom()
    )
  end

  defp pan_view(assigns, params) do
    dx = parse_float(params["dx"], 0.0)
    dy = parse_float(params["dy"], 0.0)
    display_width = max(parse_float(params["display_width"], assigns.map_width), 1.0)
    display_height = max(parse_float(params["display_height"], assigns.map_height), 1.0)

    raw_x =
      LiveMap.Tile.x(assigns.longitude, assigns.zoom) -
        dx * (assigns.map_width / display_width) / 256.0

    raw_y =
      LiveMap.Tile.y(assigns.latitude, assigns.zoom) -
        dy * (assigns.map_height / display_height) / 256.0

    %{
      latitude: LiveMap.Tile.latitude(raw_y, assigns.zoom),
      longitude: LiveMap.Tile.longitude(raw_x, assigns.zoom),
      zoom: assigns.zoom
    }
  end

  defp zoom_at(assigns, params) do
    delta = parse_integer(params["delta"], 0)
    target_zoom = clamp_zoom(assigns.zoom + delta)

    if target_zoom == assigns.zoom do
      %{
        latitude: assigns.latitude,
        longitude: assigns.longitude,
        zoom: assigns.zoom
      }
    else
      display_width = max(parse_float(params["display_width"], assigns.map_width), 1.0)
      display_height = max(parse_float(params["display_height"], assigns.map_height), 1.0)
      pointer_x = parse_float(params["x"], display_width / 2)
      pointer_y = parse_float(params["y"], display_height / 2)

      scale_x = assigns.map_width / display_width
      scale_y = assigns.map_height / display_height
      offset_x = (pointer_x - display_width / 2.0) * scale_x / 256.0
      offset_y = (pointer_y - display_height / 2.0) * scale_y / 256.0

      point_raw_x = LiveMap.Tile.x(assigns.longitude, assigns.zoom) + offset_x
      point_raw_y = LiveMap.Tile.y(assigns.latitude, assigns.zoom) + offset_y
      point_longitude = LiveMap.Tile.longitude(point_raw_x, assigns.zoom)
      point_latitude = LiveMap.Tile.latitude(point_raw_y, assigns.zoom)

      target_point_raw_x = LiveMap.Tile.x(point_longitude, target_zoom)
      target_point_raw_y = LiveMap.Tile.y(point_latitude, target_zoom)
      target_center_raw_x = target_point_raw_x - offset_x
      target_center_raw_y = target_point_raw_y - offset_y

      %{
        latitude: LiveMap.Tile.latitude(target_center_raw_y, target_zoom),
        longitude: LiveMap.Tile.longitude(target_center_raw_x, target_zoom),
        zoom: target_zoom
      }
    end
  end

  defp parse_float(nil, fallback), do: fallback
  defp parse_float(value, _fallback) when is_float(value), do: value

  defp parse_float(value, fallback) do
    case Float.parse(to_string(value)) do
      {parsed, _rest} -> parsed
      :error -> fallback
    end
  end

  defp parse_integer(nil, fallback), do: fallback
  defp parse_integer(value, _fallback) when is_integer(value), do: value

  defp parse_integer(value, fallback) do
    case Integer.parse(to_string(value)) do
      {parsed, _rest} -> parsed
      :error -> fallback
    end
  end

  defp clamp_zoom(value), do: value |> max(0) |> min(@max_zoom)

  defp clamp_latitude(value), do: value |> max(-@mercator_limit) |> min(@mercator_limit)

  defp normalize_longitude(value) do
    value
    |> Kernel.+(180.0)
    |> rem_float(360.0)
    |> Kernel.-(180.0)
  end

  defp rem_float(value, modulus) do
    value - modulus * Float.floor(value / modulus)
  end

  defp round_coordinate(value), do: Float.round(value, 6)

  attr :marker, :map, required: true
  defp place_marker(assigns) do
    palette = marker_palette(assigns.marker.id)

    assigns =
      assigns
      |> assign(:palette, palette)
      |> assign(:popover_id, "marker-#{assigns.marker.id}")

    ~H"""
    <div class="relative inline-block pointer-events-none" data-map-interactive="true">
      <button
        type="button"
        command="toggle-popover"
        commandfor={@popover_id}
        data-map-interactive="true"
        class={[
          "pointer-events-auto relative inline-flex h-11 w-11 items-center justify-center rounded-full border-2 text-xs font-bold text-white shadow-md transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-600",
          @palette.button_class
        ]}
      >
        <span
          aria-hidden="true"
          class="absolute left-1/2 top-full h-3 w-3 -translate-x-1/2 -translate-y-[0.18rem] rotate-45 rounded-[2px] border-b-2 border-r-2 border-inherit bg-inherit"
        />
        <span class={[
          "relative z-10 inline-flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-black",
          @palette.badge_class
        ]}>
          {@marker.icon}
        </span>
        <span class="sr-only">{@marker.label}</span>
      </button>

      <dialog
        id={@popover_id}
        popover=""
        data-map-interactive="true"
        class={[
          "pointer-events-auto m-auto border-0 bg-transparent p-0 text-sm text-slate-700 shadow-none backdrop:bg-slate-950/20"
        ]}
      >
        <div class="relative mt-3 inline-flex rounded-xl bg-slate-950 px-3 py-2 text-sm font-semibold text-white shadow-lg">
          <span aria-hidden="true" class="absolute left-1/2 top-0 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rotate-45 bg-slate-950"></span>
          {@marker.label}
        </div>
      </dialog>
    </div>
    """
  end

  attr :latitude, :float, required: true
  attr :longitude, :float, required: true
  attr :zoom, :integer, required: true
  defp center_marker(assigns) do
    ~H"""
    <div class="relative inline-block pointer-events-none" data-map-interactive="true">
      <button
        type="button"
        command="toggle-popover"
        commandfor="map-center-popover"
        data-map-interactive="true"
        class="pointer-events-auto relative inline-flex h-11 w-11 items-center justify-center rounded-full border-2 border-sky-900 bg-sky-600 text-white shadow-md transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-600"
      >
        <span aria-hidden="true" class="absolute left-1/2 top-full h-3 w-3 -translate-x-1/2 -translate-y-[0.18rem] rotate-45 rounded-[2px] border-b-2 border-r-2 border-inherit bg-inherit"></span>
        <span class="relative z-10 inline-flex h-5 w-5 items-center justify-center rounded-full bg-white text-[10px] font-black text-sky-700">
          C
        </span>
        <span class="sr-only">Map center</span>
      </button>

      <dialog
        id="map-center-popover"
        popover=""
        data-map-interactive="true"
        class="pointer-events-auto m-auto border-0 bg-transparent p-0 text-sm text-slate-700 shadow-none backdrop:bg-slate-950/20"
      >
        <div class="relative mt-3 min-w-56 rounded-xl bg-slate-950 px-3 py-2 text-sm text-white shadow-lg">
          <span aria-hidden="true" class="absolute left-1/2 top-0 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rotate-45 bg-slate-950"></span>
          <p class="font-semibold">Map center</p>
          <p class="mt-1 text-xs text-slate-300">
            Lat {Float.round(@latitude, 4)} | Lng {Float.round(@longitude, 4)}
          </p>
          <p class="text-xs text-slate-300">Zoom {@zoom}</p>
        </div>
      </dialog>
    </div>
    """
  end

  defp marker_palette(id) do
    case id do
      "harbor" ->
        %{
          button_class: "border-emerald-900 bg-emerald-800/95 hover:bg-emerald-700",
          badge_class: "bg-emerald-200 text-emerald-950",
        }

      "front-beach" ->
        %{
          button_class: "border-orange-900 bg-orange-600/95 hover:bg-orange-500",
          badge_class: "bg-orange-100 text-orange-950",
        }

      "back-beach" ->
        %{
          button_class: "border-sky-900 bg-sky-700/95 hover:bg-sky-600",
          badge_class: "bg-sky-100 text-sky-950",
        }

      "lighthouse" ->
        %{
          button_class: "border-rose-900 bg-rose-700/95 hover:bg-rose-600",
          badge_class: "bg-rose-100 text-rose-950",
        }

      "jesus" ->
        %{
          button_class: "border-slate-900 bg-slate-700/95 hover:bg-slate-600",
          badge_class: "bg-slate-100 text-slate-950",
        }

      "long-son" ->
        %{
          button_class: "border-lime-900 bg-lime-700/95 hover:bg-lime-600",
          badge_class: "bg-lime-100 text-lime-950",
        }
    end
  end
end

defmodule LiveMapExample.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_root_layout, html: {LiveMapExample.Layouts, :root}
  end

  scope "/" do
    pipe_through :browser

    live "/", LiveMapExample.PageLive
  end
end

defmodule LiveMapExample.Endpoint do
  use Phoenix.Endpoint, otp_app: :live_map_example

  @session_options [
    store: :cookie,
    key: "_live_map_example_key",
    signing_salt: "demo-signing-salt"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug LiveMapExample.Router
end

{opts, _argv, _invalid} =
  OptionParser.parse(System.argv(),
    strict: [port: :integer, no_start: :boolean]
  )

port = opts[:port] || 4000

Application.put_env(:live_map_example, LiveMapExample.Endpoint,
  server: true,
  url: [host: "localhost", port: port],
  http: [ip: {127, 0, 0, 1}, port: port],
  secret_key_base: String.duplicate("live-map-demo-secret-key-base-", 4),
  check_origin: false,
  live_view: [signing_salt: "demo-live-view-salt"],
  pubsub_server: LiveMapExample.PubSub,
  render_errors: [formats: [html: Phoenix.Controller], layout: false],
  debug_errors: true,
  code_reloader: false
)

if opts[:no_start] do
  IO.puts("LiveMap demo compiled successfully.")
else
  children = [
    {Phoenix.PubSub, name: LiveMapExample.PubSub},
    LiveMapExample.Endpoint
  ]

  {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)

  IO.puts("LiveMap demo running at http://localhost:#{port}")
  IO.puts("Press Ctrl+C twice to stop.")

  Process.sleep(:infinity)
end
