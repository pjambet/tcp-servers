defmodule TcpServer.Registry do
  # alias Enumerable.GenEvent
  use GenServer

  def start_link(buckets, opts \\ []) do
    GenServer.start_link(__MODULE__, buckets, opts)
  end

  def lookup(server, name) do
    GenServer.call(server, {:lookup, name})
  end

  def create(server, name) do
    GenServer.cast(server, {:create, name})
  end

  def stop(server) do
    GenServer.call(server, :stop)
  end

  ## Callbacks

  @impl true
  def init(buckets) do
    names = %{}
    refs = %{}
    {:ok, %{names: names, refs: refs, buckets: buckets}}
  end

  @impl true
  def handle_call({:lookup, name}, _from, state) do
    {:reply, Map.fetch(state.names, name), state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({:create, name}, state) do
    if(Map.has_key?(state.names, name)) do
      {:noreply, state}
    else
      {:ok, pid} = DynamicSupervisor.start_child(TcpServer.BucketSupervisor, TcpServer.Bucket)
      ref = Process.monitor(pid)
      refs = Map.put(state.refs, ref, name)
      names = Map.put(state.names, name, pid)
      {:noreply, %{state | names: names, refs: refs}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {name, refs} = Map.pop(state.refs, ref)
    names = Map.delete(state.names, name)
    # GenEvent.sync_notify(state.events, {:exit, name, pid})
    {:noreply, %{state | names: names, refs: refs}}
  end

  # def handle_info(_msg, state) do
  #   {:noreply, state}
  # end
end
