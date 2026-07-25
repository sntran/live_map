defmodule LiveMap.TestTileServer do
  def start_link do
    {:ok, state} = Agent.start_link(fn -> %{responses: %{}, requests: %{}} end)
    ref = listener_ref()
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__.ServerPlug, state, port: 0, ref: ref)
    port = :ranch.get_port(ref)

    %{state: state, ref: ref, base_url: "http://127.0.0.1:#{port}"}
  end

  def stop(server) do
    _ = Plug.Cowboy.shutdown(server.ref)

    if Process.alive?(server.state) do
      Agent.stop(server.state)
    end
  end

  def put_responses(server, path, responses) when is_list(responses) do
    Agent.update(server.state, fn state ->
      put_in(state, [:responses, path], responses)
    end)
  end

  def request_count(server, path) do
    Agent.get(server.state, fn state -> get_in(state, [:requests, path, :count]) || 0 end)
  end

  def request_headers(server, path) do
    Agent.get(server.state, fn state -> get_in(state, [:requests, path, :headers]) || [] end)
  end

  defmodule ServerPlug do
    import Plug.Conn

    def init(state), do: state

    def call(conn, state) do
      {status, headers, body} = next_response(state, conn)

      conn =
        Enum.reduce(headers, conn, fn {name, value}, acc ->
          put_resp_header(acc, name, value)
        end)

      send_resp(conn, status, body)
    end

    defp next_response(state, conn) do
      Agent.get_and_update(state, fn agent_state ->
        path = conn.request_path
        current = get_in(agent_state, [:responses, path]) || []

        {response, remaining} =
          case current do
            [next | rest] -> {next, rest}
            [] -> {{404, [{"cache-control", "max-age=0"}], "missing"}, []}
          end

        request_entry = %{
          count: (get_in(agent_state, [:requests, path, :count]) || 0) + 1,
          headers: [conn.req_headers | get_in(agent_state, [:requests, path, :headers]) || []]
        }

        next_state =
          agent_state
          |> put_in([:responses, path], remaining)
          |> put_in([:requests, path], request_entry)

        {response, next_state}
      end)
    end
  end

  defp listener_ref do
    String.to_atom("live_map_tile_test_server_#{System.unique_integer([:positive])}")
  end
end
