require "socket"
require "logger"

LOGGER = Logger.new(STDOUT)
LOGGER.level = Logger::INFO

def handle_client(db, client)
  request = client.gets
  if request.nil?
    client.close
    return nil
  end
  parts = request.split(" ")
  key = parts[1]
  value = parts[2]
  response = nil

  if request.start_with?("GET") && key
    response = db[key]
  elsif request.start_with?("SET") && key && value
    db[key] = value
    response = "OK"
  elsif request.start_with?("QUIT")
    client.close
    return nil
  else
    response = "N/A"
  end

  client.puts(response)

  response
rescue Errno::ECONNRESET => e
  LOGGER.error e
  client.close
  return nil
end

def start_server(port)
  server = TCPServer.new(port)
  clients = []
  db = {}
  LOGGER.info "Server started on port: #{ port }"

  loop do
    connected_clients =
      clients
        .delete_if { |socket| socket.closed? }

    reads, _, _ = IO.select([ server ] + connected_clients)

    reads.each do |socket|
      if socket == server
        client = server.accept
        clients << client
      else
        if handle_client(db, socket).nil?
          clients.delete(socket.fileno)
        end
      end
    rescue IOError => e
      LOGGER.error "error handling socket: #{ e }"
    end
  end
end

start_server(3000)
