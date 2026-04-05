defmodule Mixtape.RouterTest do
  use ExUnit.Case
  import Plug.Test
  import Plug.Conn

  describe "route_by_model/1" do
    test "routes coder to port 8080" do
      {:ok, url, atom} = Mixtape.Router.route_by_model("coder")
      assert url == "http://127.0.0.1:8080"
      assert atom == :coder
    end

    test "routes architect to port 8081" do
      {:ok, url, atom} = Mixtape.Router.route_by_model("architect")
      assert url == "http://127.0.0.1:8081"
      assert atom == :architect
    end

    test "defaults nil model to coder" do
      {:ok, url, atom} = Mixtape.Router.route_by_model(nil)
      assert url == "http://127.0.0.1:8080"
      assert atom == :coder
    end

    test "returns error for unknown model" do
      assert {:error, :unknown_model, "gpt-4"} = Mixtape.Router.route_by_model("gpt-4")
    end
  end

  describe "GET /health" do
    test "returns 200 with JSON model statuses" do
      conn = conn(:get, "/health")
      conn = Mixtape.Router.call(conn, Mixtape.Router.init([]))
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert is_map(body["models"])
    end
  end

  describe "POST /v1/messages" do
    test "returns 503 when model is not ready" do
      conn =
        conn(:post, "/v1/messages", %{"model" => "coder", "messages" => []})
        |> put_req_header("content-type", "application/json")

      conn = Mixtape.Router.call(conn, Mixtape.Router.init([]))

      assert conn.status == 503
      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "error"
      assert body["error"]["type"] == "overloaded_error"
    end

    test "returns 400 for unknown model" do
      conn =
        conn(:post, "/v1/messages", %{"model" => "gpt-4", "messages" => []})
        |> put_req_header("content-type", "application/json")

      conn = Mixtape.Router.call(conn, Mixtape.Router.init([]))

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "error"
      assert body["error"]["type"] == "invalid_request_error"
      assert body["error"]["message"] =~ "gpt-4"
    end
  end

  describe "POST /v1/chat/completions" do
    test "returns 503 in OpenAI error format when model is not ready" do
      conn =
        conn(:post, "/v1/chat/completions", %{"model" => "coder", "messages" => []})
        |> put_req_header("content-type", "application/json")

      conn = Mixtape.Router.call(conn, Mixtape.Router.init([]))

      assert conn.status == 503
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["type"] == "server_error"
      assert body["error"]["code"] == "service_unavailable"
    end

    test "returns 400 for unknown model in OpenAI format" do
      conn =
        conn(:post, "/v1/chat/completions", %{"model" => "gpt-4", "messages" => []})
        |> put_req_header("content-type", "application/json")

      conn = Mixtape.Router.call(conn, Mixtape.Router.init([]))

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["type"] == "invalid_request_error"
      assert body["error"]["code"] == "model_not_found"
    end
  end

  describe "catch-all" do
    test "returns 404 for unknown routes" do
      conn = conn(:get, "/unknown")
      conn = Mixtape.Router.call(conn, Mixtape.Router.init([]))
      assert conn.status == 404
    end
  end
end
