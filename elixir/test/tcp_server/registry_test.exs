defmodule TcpServer.RegistryTest do
  # alias Enumerable.GenEvent
  use ExUnit.Case

  # defmodule Forwarder do
  #   use GenEvent

  #   def handle_event(event, parent) do
  #     send(parent, event)
  #     {:ok, parent}
  #   end
  # end

  setup do
    # {:ok, manager} = GenEvent.start_link()
    {:ok, registry} = TcpServer.Registry.start_link()

    # GenEvent.add_mon_handler(manager, Forwarder, self())
    {:ok, registry: registry}
  end

  test "spawns buckets", %{registry: registry} do
    assert TcpServer.Registry.lookup(registry, "shopping") == :error

    TcpServer.Registry.create(registry, "shopping")
    assert {:ok, bucket} = TcpServer.Registry.lookup(registry, "shopping")

    TcpServer.Bucket.put(bucket, "milk", 1)
    assert TcpServer.Bucket.get(bucket, "milk") == 1
  end

  test "removes buckets on exit", %{registry: registry} do
    TcpServer.Registry.create(registry, "shopping")
    {:ok, bucket} = TcpServer.Registry.lookup(registry, "shopping")
    Agent.stop(bucket)
    assert TcpServer.Registry.lookup(registry, "shopping") == :error
  end

  # test "sends events on create on crash", %{registry: registry} do
  #   TcpServer.Registry.create(registry, "shopiing")
  #   {:ok, bucket} = TcpServer.Registry.lookup(registry, "shopping")
  #   assert_receive {:create, "shopping", ^bucket}

  #   Agent.stop(bucket)
  #   assert_receive {:exit, "shopping", ^bucket}
  # end
end
