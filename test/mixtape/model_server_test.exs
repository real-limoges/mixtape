defmodule Mixtape.ModelServerTest do
  use ExUnit.Case

  test "starts in loading state and reports not ready" do
    {:ok, pid} =
      Mixtape.ModelServer.start_link(
        name: :test_model,
        port: 19999,
        model_path: "unused",
        cmd: "cat"
      )

    refute Mixtape.ModelServer.ready?(:test_model)

    GenServer.stop(pid)
  end
end
