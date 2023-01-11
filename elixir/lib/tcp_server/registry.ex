defmodule TcpServer.Registry do
  # alias Enumerable.GenEvent
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
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

  def init(:ok) do
    names = %{}
    refs = %{}
    {:ok, %{names: names, refs: refs}}
  end

  def handle_call({:lookup, name}, _from, state) do
    {:reply, Map.fetch(state.names, name), state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_cast({:create, name}, state) do
    if(Map.has_key?(state.names, name)) do
      {:noreply, state}
    else
      {:ok, pid} = TcpServer.Bucket.start_link()
      ref = Process.monitor(pid)
      refs = Map.put(state.refs, ref, name)
      names = Map.put(state.names, name, pid)
      # GenEvent.sync_notify(state.events, {:create, name, pid})
      {:noreply, %{state | names: names, refs: refs}}
    end
  end

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
