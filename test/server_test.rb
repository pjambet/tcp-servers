require_relative "./test_helper"
require "socket"
require "securerandom"
require "timeout"

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

  it "responds to DEL" do
    with_server do
      connect_to_server do |s|
        s.puts("SET a b")
        assert_equal "OK\n", s.gets

        s.puts("GET a")
        assert_equal "b\n", s.gets

        s.puts("DEL a")
        assert_equal "1\n", s.gets

        s.puts("GET a")
        assert_equal "\n", s.gets

        s.puts("DEL a")
        assert_equal "0\n", s.gets
      end
    end
  end

  it "responds to INCR" do
    with_server do
      connect_to_server do |s|
        s.puts("SET a b")
        assert_equal "OK\n", s.gets

        s.puts("INCR a")
        assert_equal "ERR value is not an integer or out of range\n", s.gets

        s.puts("DEL a")
        assert_equal "1\n", s.gets

        s.puts("INCR a")
        assert_equal "1\n", s.gets

        s.puts("INCR a")
        assert_equal "2\n", s.gets
      end
    end
  end

  it "respond to QUIT" do
    with_server do
      connect_to_server do |s|
        s.puts("QUIT")
        s.gets
        assert s.eof?
      end
    end
  end

  it "handles multiple clients" do
    with_server do
      socket = nil

      pids = 3.times.map do
        fork do
          socket = TCPSocket.new("localhost", 3000)
          2.times do
            socket.puts "SET #{ SecureRandom.uuid } #{ rand(10) }"
            sleep 0.01
            socket.puts "GET #{ SecureRandom.uuid }"
          end
        ensure
          socket&.close
        end
      end

      pids.each do |pid|
        Process.wait(pid)
        assert_equal 0, $?.exitstatus # The exit code of the process
      end
      assert true
    end
  end

  private

  def connect_to_server
    retried = false unless retried
    socket = TCPSocket.new "localhost", 3000
    yield socket
  rescue
    unless retried
      retried = true
      retry
    end
  ensure
    socket.close if socket
  end

  def with_server
    pid = nil
    Timeout.timeout(10) do
      pid = start_server
      wait_for_server

      yield
    end
  ensure
    Process.kill("KILL", pid) if pid
    Process.wait(pid)
  end

  def start_server
    args = SERVER_CONFIG["start"] + [PORT]
    LOG.debug "Starting server with #{ args }"
    spawn(*args, STDOUT => "/dev/null", STDERR => "/dev/null")
  end

  def wait_for_server
    Timeout.timeout(2) do
      loop do
        socket = TCPSocket.new("localhost", 3000)
        socket.puts("GET a")
        socket.gets
        socket.close
        break
      rescue Errno::ECONNREFUSED => _e
        sleep 0.001
      end
    end
  end
end
