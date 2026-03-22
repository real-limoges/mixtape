defmodule Mixtape.ModelServer do
  use GenServer
  require Logger

  defstruct [:name, :port, :model_path, :cmd, :os_port, :wait_for, status: :loading]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def ready?(name) do
    GenServer.call(name, :ready?)
  end

  @impl true
  def init(opts) do
    state = struct(__MODULE__, opts)
    {:ok, state, {:continue, :spawn_model}}
  end

  @impl true
  def handle_continue(:spawn_model, %{wait_for: nil} = state) do
    {:noreply, do_spawn(state)}
  end

  def handle_continue(:spawn_model, %{wait_for: dep} = state) do
    Logger.info("Model #{state.name} waiting for #{dep} to be ready before loading")
    Process.send_after(self(), :check_dependency, 2_000)
    {:noreply, state}
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, state.status == :ready, state}
  end

  @impl true
  def handle_info(:check_dependency, %{wait_for: dep} = state) do
    {dep_url, _} = Mixtape.Router.route_by_model(Atom.to_string(dep))

    case Req.get("#{dep_url}/v1/models") do
      {:ok, %{status: 200}} ->
        Logger.info("Model #{dep} is ready, now loading #{state.name}")
        {:noreply, do_spawn(state)}

      _ ->
        Process.send_after(self(), :check_dependency, 2_000)
        {:noreply, state}
    end
  end

  def handle_info(:health_check, %{status: :ready} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    case Req.get("http://127.0.0.1:#{state.port}/v1/models") do
      {:ok, %{status: 200}} ->
        Logger.info("Model #{state.name} is ready on port #{state.port}")
        {:noreply, %{state | status: :ready}}

      _ ->
        Process.send_after(self(), :health_check, 2_000)
        {:noreply, state}
    end
  end

  def handle_info({_port, {:exit_status, code}}, state) do
    Logger.error("Model #{state.name} exited with code #{code}")
    {:stop, :model_crashed, state}
  end

  def handle_info({_port, {:data, data}}, state) do
    Logger.debug("[#{state.name}] #{data}")
    {:noreply, state}
  end

  defp do_spawn(state) do
    cmd = state.cmd || mlx_cmd(state)
    os_port = Port.open({:spawn, cmd}, [:binary, :exit_status])
    Process.send_after(self(), :health_check, 2_000)
    %{state | os_port: os_port}
  end

  defp mlx_cmd(%{model_path: path, port: port}) do
    "mlx_lm.server --model #{path} --port #{port} --host 127.0.0.1"
  end
end
