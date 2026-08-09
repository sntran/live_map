defmodule LiveMap.ViewTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint LiveMapTestApp.Endpoint

  alias LiveMap.View

  doctest View

  setup do
    [conn: Phoenix.ConnTest.build_conn()]
  end

  test "disconnected and connected mount", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "</svg>"

    {:ok, _view, html} = live(conn, "/")
    assert html =~ "</svg>"
  end

  test "takes assigns from params", %{conn: conn} do
    conn = get(conn, "/", %{width: 800, height: 600})
    assert html_response(conn, 200) =~ "width=\"800\" height=\"600\""
  end

  test "takes a Google-style center from params", %{conn: conn} do
    conn = get(conn, "/", %{center: "10,20", zoom: 1})
    html = html_response(conn, 200)

    assert html =~ "data-live-map-zoom=\"1\""
    assert html =~ "https://tile.openstreetmap.org/1/1/0.png"
  end
end
