defmodule Mixtape.Router do
  use Plug.Router

  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  post "/v1/messages" do
    case route_by_model(conn.body_params["model"]) do
      {:error, :unknown_model, name} ->
        send_json(conn, 400, %{
          type: "error",
          error: %{type: "invalid_request_error", message: "Unknown model: #{name}"}
        })

      {:ok, upstream_url, model_atom} ->
        if Mixtape.ModelServer.ready?(model_atom) do
          model_name = conn.body_params["model"] || "coder"
          Mixtape.StreamForwarder.forward(conn, upstream_url, model_name)
        else
          send_json(conn, 503, %{
            type: "error",
            error: %{
              type: "overloaded_error",
              message:
                "Model '#{model_atom}' is not available. Ensure the MLX-LM server is running on the expected port."
            }
          })
        end
    end
  end

  post "/v1/chat/completions" do
    case route_by_model(conn.body_params["model"]) do
      {:error, :unknown_model, name} ->
        send_json(conn, 400, %{
          error: %{
            message: "Unknown model: #{name}",
            type: "invalid_request_error",
            code: "model_not_found"
          }
        })

      {:ok, upstream_url, model_atom} ->
        if Mixtape.ModelServer.ready?(model_atom) do
          Mixtape.StreamForwarder.forward_raw(conn, upstream_url, conn.body_params)
        else
          send_json(conn, 503, %{
            error: %{
              message:
                "Model '#{model_atom}' is not available. Ensure the MLX-LM server is running on the expected port.",
              type: "server_error",
              code: "service_unavailable"
            }
          })
        end
    end
  end

  get "/health" do
    statuses = %{
      coder: Mixtape.ModelServer.status(:coder),
      architect: Mixtape.ModelServer.status(:architect)
    }

    send_json(conn, 200, %{status: "ok", models: statuses})
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  def route_by_model("coder"), do: {:ok, "http://127.0.0.1:8080", :coder}
  def route_by_model("architect"), do: {:ok, "http://127.0.0.1:8081", :architect}
  def route_by_model(nil), do: {:ok, "http://127.0.0.1:8080", :coder}
  def route_by_model(unknown), do: {:error, :unknown_model, unknown}

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
