defmodule LiveMap.Application do
  @moduledoc false
  # The process of the cache of the PMTiles archives (LiveMap.PMTiles).

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([LiveMap.PMTiles.Cache],
      strategy: :one_for_one,
      name: LiveMap.Supervisor
    )
  end
end

defmodule LiveMap.PMTiles.Cache do
  @moduledoc false
  # The owner of the ETS table of LiveMap.PMTiles: the headers, the root
  # directories and some leaf directories of the archives.

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(LiveMap.PMTiles, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, nil}
  end
end
