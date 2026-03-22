defmodule Mixtape.RouterTest do
  use ExUnit.Case
  import Plug.Test
  import Plug.Conn

  describe "route_by_model/1" do
    test "routes coder to port 8080" do
      {url, atom} = Mixtape.Router.route_by_model("coder")
      assert url == "http://127.0.0.1:8080"
      assert atom == :coder
    end

    test "routes architect to port 8081" do
      {url, atom} = Mixtape.Router.route_by_model("architect")
      assert url == "http://127.0.0.1:8081"
      assert atom == :architect
    end

    test "defaults unknown model to coder" do
      {url, atom} = Mixtape.Router.route_by_model("unknown")
      assert url == "http://127.0.0.1:8080"
      assert atom == :coder
    end
  end

  describe "GET /health" do
    test "returns 200 ok" do
      conn = conn(:get, "/health")
      conn = Mixtape.Router.call(conn, Mixtape.Router.init([]))
      assert conn.status == 200
      assert conn.resp_body == "ok"
    end
  end

  describe "POST /v1/messages" do
    test "returns 503 when model is not ready" do
      # The app supervisor already starts :coder in :loading state
      # (mlx_lm isn't available in the test environment)
      conn =
        conn(:post, "/v1/messages", %{"model" => "coder", "messages" => []})
        |> put_req_header("content-type", "application/json")

      conn = Mixtape.Router.call(conn, Mixtape.Router.init([]))

      assert conn.status == 503
      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "error"
      assert body["error"]["type"] == "overloaded_error"
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
      assert body["error"]["message"] == "Model is still loading"
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
