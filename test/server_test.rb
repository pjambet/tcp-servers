require_relative './test_helper'
require 'socket'
require 'securerandom'
require 'timeout'

describe "A server" do
  it "can be connected to" do
    with_server do
      connect_to_server do |s|
        assert s
      end
    end
  end

  it "responds to GET" do
    with_server do
      connect_to_server do |s|
        s.puts("GET a")
        assert_equal "\n", s.gets

        s.puts("GET b")
        assert_equal "\n", s.gets
      end
    end
  end

  it "responds to SET" do
    with_server do
      connect_to_server do |s|
        s.puts("SET a b")
        assert_equal "OK\n", s.gets

        s.puts("GET a")
        assert_equal "b\n", s.gets
      end
    end
  end

  it "respond to QUIT" do
    with_server do
      connect_to_server do |s|
        s.puts("QUIT")
        assert s.eof?
      end
    end
  end

  it "handles multiple clients" do
    with_server do
      socket = nil

      loop do
        begin
          socket = TCPSocket.new('localhost', 7878)
          break
        rescue Errno::ECONNREFUSED => _e
          sleep 0.001
        end
      end

      pids = 3.times.map do
        run_in_process do
          socket = TCPSocket.new('localhost', 7878)
          2.times do
            socket.puts "SET #{ SecureRandom.uuid } #{ rand(10) }"
            sleep 0.01
            socket.puts "GET #{ SecureRandom.uuid }"
          end
        end
      end

      pids.each { |pid| Process.wait(pid) }
      assert true
    end
  end

  def run_in_process
    fork do
      yield
    end
  end

  def connect_to_server
    socket = nil
    Timeout.timeout(5) do
      loop do
        begin
          socket = TCPSocket.new 'localhost', 7878
          yield socket
          break
        rescue StandardError => e
          sleep 0.1
        end
      end
    end
  ensure
    socket.close if socket
  end

  def with_server
    system("go build -o ./go/server go/server.go") # unless File.exist?("./go/server")
    pid = spawn("./go/server 7878", STDOUT => "/dev/null")

    yield

  ensure
    if pid
      Process.kill('KILL', pid)
    end
  end
end
