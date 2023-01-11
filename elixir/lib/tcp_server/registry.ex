defmodule TcpServer.Registry do
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
    names = HashDict.new()
    refs = HashDict.new()
    {:ok, {names, refs}}
  end

  def handle_call({:lookup, name}, _from, {names, _} = state) do
    {:reply, HashDict.fetch(names, name), state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_cast({:create, name}, {names, refs}) do
    if(HashDict.has_key?(names, name)) do
      {:noreply, {names, refs}}
    else
      {:ok, pid} = TcpServer.Bucket.start_link()
      ref = Process.monitor(pid)
      refs = HashDict.put(refs, ref, name)
      names = HashDict.put(names, name, pid)
      {:noreply, {names, refs}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, {names, refs}) do
    {name, refs} = HashDict.pop(refs, ref)
    names = HashDict.delete(names, name)
    {:noreply, {names, refs}}
  end
end
