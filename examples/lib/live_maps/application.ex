defmodule LiveMaps.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      LiveMapsWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: LiveMaps.PubSub},
      # Start the Endpoint (http/https)
      LiveMapsWeb.Endpoint
      # Start a worker by calling: LiveMaps.Worker.start_link(arg)
      # {LiveMaps.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LiveMaps.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LiveMapsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
