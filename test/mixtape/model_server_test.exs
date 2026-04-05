defmodule Mixtape.ModelServerTest do
  use ExUnit.Case

  describe "health checking" do
    test "starts in :down status and reports not ready" do
      bypass = Bypass.open()
      Bypass.down(bypass)

      name = :"test_model_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Mixtape.ModelServer.start_link(
          name: name,
          port: bypass.port,
          health_interval: 50
        )

      refute Mixtape.ModelServer.ready?(name)

      GenServer.stop(pid)
    end

    test "transitions to :up when upstream responds 200" do
      bypass = Bypass.open()

      Bypass.expect(bypass, "GET", "/v1/models", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{data: []}))
      end)

      name = :"test_model_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Mixtape.ModelServer.start_link(
          name: name,
          port: bypass.port,
          health_interval: 50
        )

      Process.sleep(150)
      assert Mixtape.ModelServer.ready?(name)

      GenServer.stop(pid)
    end

    test "transitions back to :down when upstream stops responding" do
      bypass = Bypass.open()

      Bypass.expect(bypass, "GET", "/v1/models", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{data: []}))
      end)

      name = :"test_model_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Mixtape.ModelServer.start_link(
          name: name,
          port: bypass.port,
          health_interval: 50
        )

      Process.sleep(150)
      assert Mixtape.ModelServer.ready?(name)

      Bypass.down(bypass)
      Process.sleep(150)
      refute Mixtape.ModelServer.ready?(name)

      GenServer.stop(pid)
    end
  end

  describe "ready?/1" do
    test "returns false for unregistered name" do
      refute Mixtape.ModelServer.ready?(:nonexistent_model)
    end
  end

  describe "status/1" do
    test "returns :not_configured for unregistered name" do
      result = Mixtape.ModelServer.status(:nonexistent_model)
      assert result == %{name: :nonexistent_model, status: :not_configured}
    end

    test "returns full status for running server" do
      bypass = Bypass.open()
      Bypass.down(bypass)

      name = :"test_model_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Mixtape.ModelServer.start_link(
          name: name,
          port: bypass.port,
          health_interval: 50
        )

      result = Mixtape.ModelServer.status(name)
      assert result.name == name
      assert result.port == bypass.port
      assert result.status == :down

      GenServer.stop(pid)
    end
  end
end
