defmodule TcpServer.BucketTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, bucket} = TcpServer.Bucket.start_link()
    {:ok, bucket: bucket}
  end

  test "stores values by key", %{bucket: bucket} do
    assert TcpServer.Bucket.get(bucket, "milk") == nil

    TcpServer.Bucket.put(bucket, "milk", 3)
    assert TcpServer.Bucket.get(bucket, "milk") == 3
  end

  test "deletes values by key", %{bucket: bucket} do
    assert TcpServer.Bucket.delete(bucket, "milk") == nil

    TcpServer.Bucket.put(bucket, "milk", 3)
    assert TcpServer.Bucket.get(bucket, "milk") == 3

    assert TcpServer.Bucket.delete(bucket, "milk") == 3
    assert TcpServer.Bucket.delete(bucket, "milk") == nil
  end
end
