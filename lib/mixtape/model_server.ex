defmodule Mixtape.ModelServer do
  use GenServer
  require Logger

  defstruct [:name, :port, :url, status: :down, health_interval: 5_000]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def ready?(name) do
    GenServer.call(name, :ready?)
  catch
    :exit, _ -> false
  end

  def status(name) do
    GenServer.call(name, :status)
  catch
    :exit, _ -> %{name: name, status: :not_configured}
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      name: opts[:name],
      port: opts[:port],
      url: "http://127.0.0.1:#{opts[:port]}",
      health_interval: opts[:health_interval] || 5_000
    }

    Process.send_after(self(), :health_check, 0)
    {:ok, state}
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, state.status == :up, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, %{name: state.name, port: state.port, status: state.status}, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_status =
      case Req.get("#{state.url}/v1/models",
             receive_timeout: 3_000,
             connect_options: [timeout: 2_000],
             retry: false
           ) do
        {:ok, %{status: 200}} -> :up
        _ -> :down
      end

    if new_status != state.status do
      Logger.info("Model #{state.name} is now #{new_status} on port #{state.port}")
    end

    Process.send_after(self(), :health_check, state.health_interval)
    {:noreply, %{state | status: new_status}}
  end
end
