defmodule Mixtape.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Supervisor.child_spec(
        {Mixtape.ModelServer, name: :coder, port: 8080},
        id: :model_server_coder
      ),
      Supervisor.child_spec(
        {Mixtape.ModelServer, name: :architect, port: 8081},
        id: :model_server_architect
      ),
      {Bandit, plug: Mixtape.Router, port: 4000}
    ]

    opts = [strategy: :one_for_one, name: Mixtape.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
