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
    <html lang="en" class="h-full bg-white">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>LiveMap Demo</title>
        <script src="https://cdn.tailwindcss.com?plugins=forms"></script>
      </head>
      <body class="min-h-full bg-slate-100 text-slate-950 antialiased">
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
    <main class="mx-auto flex min-h-screen w-full max-w-7xl items-center px-4 py-6 sm:px-6 lg:px-8">
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
  @marker_visibility_km 12.0
  @static_marker %{
    id: "harbor",
    short: "HB",
    label: "Harbor",
    category: "Working waterfront",
    description:
      "A sheltered edge of Vung Tau where ferries, fishing boats, and cargo traffic keep the city tied to the sea every day.",
    latitude: 10.411379,
    longitude: 107.136224
  }
  @markers [
    %{
      id: "front-beach",
      short: "FB",
      label: "Front Beach",
      category: "Promenade",
      description:
        "A calmer waterfront with cafés, palms, and a long curve of shoreline that feels especially alive at sunset.",
      latitude: 10.33686,
      longitude: 107.08479
    },
    %{
      id: "back-beach",
      short: "BB",
      label: "Back Beach",
      category: "Open coast",
      description:
        "The broader surf-facing stretch of Vung Tau, known for sea breeze, morning exercise, and long sandy views.",
      latitude: 10.33454,
      longitude: 107.09652
    },
    %{
      id: "lighthouse",
      short: "LH",
      label: "Vung Tau Lighthouse",
      category: "Hilltop lookout",
      description:
        "A historic beacon above the city, with winding roads, sea air, and one of the clearest panoramic views in Vung Tau.",
      latitude: 10.34618,
      longitude: 107.0843
    },
    %{
      id: "jesus",
      short: "CV",
      label: "Christ of Vung Tau",
      category: "Monument",
      description:
        "The giant hillside statue that defines the skyline, reached by a climb that opens up broad views over the coast.",
      latitude: 10.34138,
      longitude: 107.09304
    },
    %{
      id: "long-son",
      short: "LS",
      label: "Long Son",
      category: "Island edge",
      description:
        "A quieter side of the region, where water, low hills, and fishing activity create a gentler rhythm beyond the city center.",
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
      |> assign(:static_marker, @static_marker)
     |> assign(:latitude, 10.4197639)
     |> assign(:longitude, 107.1070841)
     |> assign(:zoom, 11)}
  end

  @impl true
  def handle_event("change", params, socket) do
    {:noreply, assign_view(socket, params)}
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
    <section class="flex w-full flex-col gap-6 rounded-3xl border border-slate-300 bg-white p-4 shadow-sm md:p-6 lg:p-8">
      <div class="space-y-4">
        <div class="inline-flex items-center gap-2 rounded-full border border-slate-300 bg-slate-100 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-slate-700">
          <span class="h-2 w-2 rounded-full bg-slate-700"></span>
          Single-file demo
        </div>

        <div class="space-y-3">
          <h1 class="text-4xl font-semibold tracking-tight text-slate-950 sm:text-5xl">
            LiveMap
          </h1>
          <p class="max-w-3xl text-sm leading-7 text-slate-700 sm:text-base">
            A minimal Phoenix LiveView endpoint packaged as one script. Change the coordinates,
            drag the map, or use the mouse wheel to demonstrate how the server keeps map state,
            form state, a single explicit marker, and a parent-filtered `:for` marker set aligned.
          </p>
        </div>
      </div>

      <div class="relative overflow-hidden rounded-[1.75rem] border border-slate-300 bg-slate-200 p-2 shadow-sm">
        <div class="pointer-events-none absolute inset-x-0 top-0 z-10 p-3 sm:p-4">
          <div class="pointer-events-auto flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <form class="grid flex-1 gap-2 rounded-2xl border border-slate-300 bg-white p-2 shadow-sm sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_8rem] sm:p-3" phx-change="change" phx-submit="change">
              <label class="grid gap-1">
                <span class="sr-only">Latitude</span>
                <span class="text-[10px] font-semibold uppercase tracking-[0.16em] text-slate-700">Lat</span>
                <input
                  id="latitude"
                  name="latitude"
                  value={@latitude}
                  inputmode="decimal"
                  class="block w-full rounded-lg border-slate-300 bg-white px-3 py-2 text-sm text-slate-950 placeholder:text-slate-500 focus:border-sky-600 focus:ring-2 focus:ring-sky-600"
                />
              </label>

              <label class="grid gap-1">
                <span class="sr-only">Longitude</span>
                <span class="text-[10px] font-semibold uppercase tracking-[0.16em] text-slate-700">Lng</span>
                <input
                  id="longitude"
                  name="longitude"
                  value={@longitude}
                  inputmode="decimal"
                  class="block w-full rounded-lg border-slate-300 bg-white px-3 py-2 text-sm text-slate-950 placeholder:text-slate-500 focus:border-sky-600 focus:ring-2 focus:ring-sky-600"
                />
              </label>

              <label class="grid gap-1">
                <span class="sr-only">Zoom</span>
                <span class="text-[10px] font-semibold uppercase tracking-[0.16em] text-slate-700">Zoom</span>
                <input
                  id="zoom"
                  name="zoom"
                  value={@zoom}
                  type="number"
                  min="0"
                  max="18"
                  class="block w-full rounded-lg border-slate-300 bg-white px-3 py-2 text-sm text-slate-950 placeholder:text-slate-500 focus:border-sky-600 focus:ring-2 focus:ring-sky-600"
                />
              </label>
            </form>

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
            Drag the map to pan, use the mouse wheel to zoom, or click the built-in zoom controls.
            Every interaction round-trips through LiveView so the inputs stay in sync.
          </div>
        </div>

        <div class="pointer-events-none absolute inset-x-0 top-0 h-24 bg-gradient-to-b from-slate-200/80 to-transparent"></div>

        <div
          id="map-viewport"
          phx-hook="MapViewport"
          data-latitude={@latitude}
          data-longitude={@longitude}
          data-zoom={@zoom}
          class="relative aspect-video w-full cursor-grab touch-none overflow-hidden rounded-2xl border border-slate-300 bg-white"
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
              id={@static_marker.id}
              latitude={@static_marker.latitude}
              longitude={@static_marker.longitude}
              label={@static_marker.label}
            >
              <.place_marker marker={@static_marker} />
            </:marker>

            <:marker
              :for={marker <- visible_markers(@latitude, @longitude)}
              id={marker.id}
              latitude={marker.latitude}
              longitude={marker.longitude}
              label={marker.label}
            >
              <.place_marker marker={marker} />
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
      </div>
    </section>
    """
  end

  defp assign_view(socket, params) do
    assign(socket,
      latitude: params |> value_for(:latitude, socket.assigns.latitude) |> clamp_latitude() |> round_coordinate(),
      longitude: params |> value_for(:longitude, socket.assigns.longitude) |> normalize_longitude() |> round_coordinate(),
      zoom: params |> value_for(:zoom, socket.assigns.zoom) |> clamp_zoom()
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

  defp value_for(params, field, fallback) do
    case field do
      :zoom -> parse_zoom(params[Atom.to_string(field)] || params[field], fallback)
      _ -> parse_float(params[Atom.to_string(field)] || params[field], fallback)
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

  defp parse_zoom(nil, fallback), do: fallback
  defp parse_zoom(value, _fallback) when is_integer(value), do: clamp_zoom(value)

  defp parse_zoom(value, fallback) do
    value |> parse_integer(fallback) |> clamp_zoom()
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
          "pointer-events-auto inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-xs font-bold text-white shadow-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-600",
          @palette.button_class
        ]}
      >
        <span class={[
          "inline-flex h-6 w-6 items-center justify-center rounded-full text-[10px] font-black",
          @palette.badge_class
        ]}>
          {@marker.short}
        </span>
        {@marker.label}
      </button>

      <dialog
        id={@popover_id}
        popover=""
        data-map-interactive="true"
        class={[
          "pointer-events-auto m-auto w-64 rounded-2xl border bg-white p-0 text-sm text-slate-700 shadow-xl backdrop:bg-slate-950/20",
          @palette.dialog_class,
        ]}
      >
        <div class="overflow-hidden rounded-[inherit]">
          <div class={[
            "flex items-start justify-between border-b px-4 py-3",
            @palette.header_class
          ]}>
            <div class="space-y-1">
              <p class="text-sm font-semibold text-slate-950">{@marker.label}</p>
              <p class="text-xs font-medium uppercase tracking-[0.14em] text-slate-600">
                {@marker.category}
              </p>
            </div>

            <button
              type="button"
              command="hide-popover"
              commandfor={@popover_id}
              data-map-interactive="true"
              class="rounded-full border border-slate-300 px-2 py-1 text-[11px] font-semibold text-slate-700 transition hover:bg-white/70"
            >
              Close
            </button>
          </div>

          <.place_postcard marker={@marker} palette={@palette} />

          <div class="space-y-3 p-4">
            <p>{@marker.description}</p>
            <p>
              <strong>Coordinates:</strong>
              {Float.round(@marker.latitude, 4)},
              {Float.round(@marker.longitude, 4)}
            </p>
            <a
              href="https://www.openstreetmap.org/"
              target="_blank"
              rel="noreferrer"
              data-map-interactive="true"
              class={[
                "font-semibold underline underline-offset-2",
                @palette.link_class
              ]}
            >
              OpenStreetMap
            </a>
          </div>
        </div>
      </dialog>
    </div>
    """
  end

  attr :marker, :map, required: true
  attr :palette, :map, required: true
  defp place_postcard(assigns) do
    ~H"""
    <div class={[
      "relative h-28 overflow-hidden border-b",
      @palette.postcard_class
    ]}>
      <svg viewBox="0 0 256 112" class="h-full w-full" aria-hidden="true">
        <defs>
          <linearGradient id={"sky-#{@marker.id}"} x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stop-color={@palette.sky_start} />
            <stop offset="100%" stop-color={@palette.sky_end} />
          </linearGradient>
          <linearGradient id={"sea-#{@marker.id}"} x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stop-color={@palette.sea_start} />
            <stop offset="100%" stop-color={@palette.sea_end} />
          </linearGradient>
        </defs>

        <rect width="256" height="112" fill={"url(#sky-#{@marker.id})"} />
        <circle cx="208" cy="22" r="13" fill="rgba(255,255,255,0.72)" />
        <rect y="68" width="256" height="44" fill={"url(#sea-#{@marker.id})"} />

        <%= case @marker.id do %>
          <% "harbor" -> %>
            <rect x="18" y="56" width="72" height="10" rx="4" fill="#0f172a" opacity="0.16" />
            <rect x="24" y="48" width="34" height="18" rx="4" fill="#334155" />
            <rect x="78" y="44" width="44" height="22" rx="4" fill="#1f2937" />
            <path d="M148 69h42l-8 12h-30z" fill="#0f766e" />
            <path d="M165 38v31" stroke="#f8fafc" stroke-width="4" stroke-linecap="round" />
            <path d="M165 41l17 9h-17z" fill="#f8fafc" />
          <% "front-beach" -> %>
            <path d="M0 82c18-8 35-8 53 0s35 8 53 0 35-8 53 0 35 8 53 0 35-8 53 0v30H0z" fill="#0284c7" opacity="0.82" />
            <path d="M0 90c18-8 35-8 53 0s35 8 53 0 35-8 53 0 35 8 53 0 35-8 53 0" fill="none" stroke="#e0f2fe" stroke-width="4" stroke-linecap="round" />
            <path d="M84 68l16-22 16 22z" fill="#fb923c" />
            <path d="M100 46v32" stroke="#52525b" stroke-width="4" stroke-linecap="round" />
          <% "back-beach" -> %>
            <path d="M0 72c28 10 56 10 84 0s56-10 84 0 56 10 88 0v40H0z" fill="#0ea5e9" opacity="0.82" />
            <path d="M0 88c28 10 56 10 84 0s56-10 84 0 56 10 88 0" fill="none" stroke="#dbeafe" stroke-width="4" stroke-linecap="round" />
            <path d="M170 40c18 0 34 6 48 18-18 7-35 10-52 10-11 0-22-2-34-6 10-14 22-22 38-22z" fill="#94a3b8" opacity="0.5" />
          <% "lighthouse" -> %>
            <rect x="102" y="34" width="22" height="42" rx="4" fill="#f8fafc" />
            <rect x="98" y="28" width="30" height="10" rx="4" fill="#ef4444" />
            <path d="M113 14v14" stroke="#475569" stroke-width="4" stroke-linecap="round" />
            <path d="M128 36l58-18v20l-58 10z" fill="#fde68a" opacity="0.78" />
            <path d="M42 84c28-18 54-18 82 0s54 18 90 0v28H42z" fill="#1d4ed8" opacity="0.7" />
          <% "jesus" -> %>
            <path d="M118 24c6 0 11 5 11 11s-5 11-11 11-11-5-11-11 5-11 11-11z" fill="#f8fafc" />
            <path d="M118 46v34" stroke="#f8fafc" stroke-width="9" stroke-linecap="round" />
            <path d="M90 54h56" stroke="#f8fafc" stroke-width="8" stroke-linecap="round" />
            <path d="M72 86c28-22 58-22 90 0v26H72z" fill="#475569" opacity="0.82" />
          <% "long-son" -> %>
            <path d="M18 80c24-22 52-22 84 0s60 22 92 0v32H18z" fill="#16a34a" opacity="0.82" />
            <path d="M144 80c16-8 34-8 54 0" fill="none" stroke="#f8fafc" stroke-width="4" stroke-linecap="round" />
            <path d="M30 65h70" stroke="#f8fafc" stroke-width="5" stroke-linecap="round" />
            <path d="M48 64l10-20 10 20" fill="#f8fafc" opacity="0.92" />
          <% _ -> %>
            <rect x="52" y="34" width="152" height="48" rx="18" fill="#ffffff" opacity="0.48" />
        <% end %>
      </svg>
    </div>
    """
  end

  defp marker_palette(id) do
    case id do
      "harbor" ->
        %{
          pin_fill: "#0f766e",
          button_class: "border-emerald-900 bg-emerald-800/95 hover:bg-emerald-700",
          badge_class: "bg-emerald-200 text-emerald-950",
          dialog_class: "border-emerald-200",
          header_class: "bg-emerald-50",
          postcard_class: "border-emerald-100",
          link_class: "text-emerald-700",
          sky_start: "#d1fae5",
          sky_end: "#ecfeff",
          sea_start: "#0f766e",
          sea_end: "#0f766e"
        }

      "front-beach" ->
        %{
          pin_fill: "#f97316",
          button_class: "border-orange-900 bg-orange-600/95 hover:bg-orange-500",
          badge_class: "bg-orange-100 text-orange-950",
          dialog_class: "border-orange-200",
          header_class: "bg-orange-50",
          postcard_class: "border-orange-100",
          link_class: "text-orange-700",
          sky_start: "#fed7aa",
          sky_end: "#fffbeb",
          sea_start: "#fb923c",
          sea_end: "#ea580c"
        }

      "back-beach" ->
        %{
          pin_fill: "#0284c7",
          button_class: "border-sky-900 bg-sky-700/95 hover:bg-sky-600",
          badge_class: "bg-sky-100 text-sky-950",
          dialog_class: "border-sky-200",
          header_class: "bg-sky-50",
          postcard_class: "border-sky-100",
          link_class: "text-sky-700",
          sky_start: "#dbeafe",
          sky_end: "#e0f2fe",
          sea_start: "#0ea5e9",
          sea_end: "#0369a1"
        }

      "lighthouse" ->
        %{
          pin_fill: "#dc2626",
          button_class: "border-rose-900 bg-rose-700/95 hover:bg-rose-600",
          badge_class: "bg-rose-100 text-rose-950",
          dialog_class: "border-rose-200",
          header_class: "bg-rose-50",
          postcard_class: "border-rose-100",
          link_class: "text-rose-700",
          sky_start: "#ffe4e6",
          sky_end: "#fef2f2",
          sea_start: "#fca5a5",
          sea_end: "#dc2626"
        }

      "jesus" ->
        %{
          pin_fill: "#475569",
          button_class: "border-slate-900 bg-slate-700/95 hover:bg-slate-600",
          badge_class: "bg-slate-100 text-slate-950",
          dialog_class: "border-slate-200",
          header_class: "bg-slate-50",
          postcard_class: "border-slate-100",
          link_class: "text-slate-700",
          sky_start: "#e2e8f0",
          sky_end: "#f8fafc",
          sea_start: "#94a3b8",
          sea_end: "#475569"
        }

      "long-son" ->
        %{
          pin_fill: "#16a34a",
          button_class: "border-lime-900 bg-lime-700/95 hover:bg-lime-600",
          badge_class: "bg-lime-100 text-lime-950",
          dialog_class: "border-lime-200",
          header_class: "bg-lime-50",
          postcard_class: "border-lime-100",
          link_class: "text-lime-700",
          sky_start: "#dcfce7",
          sky_end: "#f7fee7",
          sea_start: "#4ade80",
          sea_end: "#16a34a"
        }
    end
  end

  defp visible_markers(latitude, longitude) do
    Enum.filter(@markers, fn marker ->
      distance_km(latitude, longitude, marker.latitude, marker.longitude) <= @marker_visibility_km
    end)
  end

  defp distance_km(latitude_a, longitude_a, latitude_b, longitude_b) do
    earth_radius_km = 6371.0
    latitude_delta = degrees_to_radians(latitude_b - latitude_a)
    longitude_delta = degrees_to_radians(longitude_b - longitude_a)
    latitude_a = degrees_to_radians(latitude_a)
    latitude_b = degrees_to_radians(latitude_b)

    haversine =
      :math.sin(latitude_delta / 2) * :math.sin(latitude_delta / 2) +
        :math.cos(latitude_a) * :math.cos(latitude_b) *
          :math.sin(longitude_delta / 2) * :math.sin(longitude_delta / 2)

    2 * earth_radius_km * :math.atan2(:math.sqrt(haversine), :math.sqrt(1 - haversine))
  end

  defp degrees_to_radians(degrees), do: degrees * :math.pi() / 180.0
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
