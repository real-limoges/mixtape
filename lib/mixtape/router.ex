defmodule Mixtape.Router do
  use Plug.Router

  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  post "/v1/messages" do
    {upstream_url, model_atom} = route_by_model(conn.body_params["model"])
    model_name = conn.body_params["model"] || "coder"

    if Mixtape.ModelServer.ready?(model_atom) do
      Mixtape.StreamForwarder.forward(conn, upstream_url, model_name)
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        503,
        Jason.encode!(%{
          type: "error",
          error: %{
            type: "overloaded_error",
            message: "Model is still loading"
          }
        })
      )
    end
  end

  post "/v1/chat/completions" do
    {upstream_url, model_atom} = route_by_model(conn.body_params["model"])

    if Mixtape.ModelServer.ready?(model_atom) do
      Mixtape.StreamForwarder.forward_raw(conn, upstream_url, conn.body_params)
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        503,
        Jason.encode!(%{
          error: %{
            message: "Model is still loading",
            type: "server_error",
            code: "service_unavailable"
          }
        })
      )
    end
  end

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  def route_by_model("coder"), do: {"http://127.0.0.1:8080", :coder}
  def route_by_model("architect"), do: {"http://127.0.0.1:8081", :architect}
  def route_by_model(_), do: {"http://127.0.0.1:8080", :coder}
end
