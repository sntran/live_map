defmodule LiveMapsWeb.PageController do
  use LiveMapsWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
