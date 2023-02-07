defmodule TcpServer.RegistryTest do
  use ExUnit.Case, async: true

  setup do
    registry = start_supervised!(TcpServer.Registry)
    %{registry: registry}
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

  test "removes buckets on crash", %{registry: registry} do
    TcpServer.Registry.create(registry, "shopping")
    {:ok, bucket} = TcpServer.Registry.lookup(registry, "shopping")

    # Stop the bucket with non-normal reason
    Agent.stop(bucket, :shutdown)
    assert TcpServer.Registry.lookup(registry, "shopping") == :error
  end
end
