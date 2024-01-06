# frozen_string_literal: true

require "socket"
require "logger"

LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO

def handle_client(db, client)
  request = client.gets
  if request.nil?
    client.close
    return nil
  end
  parts = request.split(" ")
  command = parts[0]
  key = parts[1]
  value = parts[2]
  response = nil

  case
  when command == "GET" && key
    if key
      response = db[key] || ""
    else
      ""
    end
  when command == "SET" && key && value
    db[key] = value
    response = "OK"
  when command == "DEL" && key
    if db[key]
      db.delete(key)
      response = "1"
    else
      response = "0"
    end
  when command == "INCR" && key
    existing = db[key]
    if existing
      begin
        int_value = Integer(existing)
        response = (int_value + 1).to_s
        db[key] = response
      rescue ArgumentError
        response = "ERR value is not an integer or out of range"
      end
    else
      response = "1"
      db[key] = "1"
    end
  when command == "QUIT"
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
  nil
end

def start_server(port)
  server = TCPServer.new(port)
  clients = Set.new
  db = {}
  LOGGER.info "Server started on port: #{ port }"

  loop do
    sockets = clients.to_a << server
    reads, = IO.select(sockets)

    reads.each do |readable_socket|
      if readable_socket == server
        client = server.accept
        clients << client
      elsif handle_client(db, readable_socket).nil?
        clients.delete(readable_socket)
      end
    rescue IOError => e
      LOGGER.error "error handling socket: #{ e }"
    end
  end
end

start_server(3000)
