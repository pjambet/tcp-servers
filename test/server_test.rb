require_relative './test_helper'
require 'socket'
require 'securerandom'
require 'timeout'

describe "A server" do
  it "can be connected to" do
    with_server do |s|
      assert s
    end
  end

  it "responds to GET" do
    with_server do |s|
      s.puts("GET a")
      assert_equal "\n", s.gets

      s.puts("GET b")
      assert_equal "\n", s.gets
    end
  end

  it "responds to SET" do
    with_server do |s|
      s.puts("SET a b")
      assert_equal "OK\n", s.gets

      s.puts("GET a")
      assert_equal "b\n", s.gets
    end
  end

  it "respond to QUIT" do
    with_server do |s|
      s.puts("QUIT")
      assert s.eof?
    end
  end

  it "handles multiple clients" do
    server_pid = spawn("./go/server 7878 > /dev/null 2>&1")
    socket = nil
    # puts socket.nil?
    # puts !socket&.nil?

    loop do
      begin
        socket = TCPSocket.new('localhost', 7878)
        # puts "CONNECTED!"
        break
      rescue Errno::ECONNREFUSED => _e
        sleep 0.001
      end
    end

    # Process.detach(server_pid)

    pids = 3.times.map do
      run_in_process do
        socket = TCPSocket.new('localhost', 7878)
        # puts "Connected"
        # puts "I'm in a different process"
        # puts Process.pid
        2.times do
          socket.puts "SET #{ SecureRandom.uuid } #{ rand(10) }"
          sleep 0.01
          socket.puts "GET #{ SecureRandom.uuid }"
        end
      end
    end

    # puts "waiting:"
    pids.each { Process.wait(_1) }
    Process.kill 'KILL', server_pid
    assert true
  end

  def run_in_process
    fork do
      yield
    end
  end

  def with_server
    system("go build -o ./go/server go/server.go") # unless File.exist?("./go/server")
    # puts Dir.getwd
    # puts system("whoami")
    pid = spawn("./go/server 7878 > /dev/null 2>&1")

    Timeout.timeout(5) do
      loop do
        begin
          socket = TCPSocket.new 'localhost', 7878
          yield socket
          break
        rescue StandardError => e
          # puts e.message
          sleep 0.1
        end
      end
    end

  ensure
    if pid
      Process.kill('KILL', pid)
    end
  end
end
