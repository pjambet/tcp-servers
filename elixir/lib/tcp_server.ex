defmodule TcpServer do
  use Application

  @moduledoc """
  Documentation for `TcpServer`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> TcpServer.hello()
      :world

  """
  def hello do
    :world
  end

  def start(_type, _args) do
    TcpServer.Supervisor.start_link(name: TcpServer.Supervisor)
  end
end
