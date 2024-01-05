import select
import socket

sockets = []
db = {}

def handle_client(client):
    sockets.append(client)

def handle_request(client):
    try:
      data = client.recv(1024).decode("utf-8").strip()
    except ConnectionResetError:
        client.close()
        del sockets[sockets.index(client)]
        return

    parts = data.split(" ")
    try:
      key = parts[1]
    except IndexError:
      key = None
    response = None

    if data.startswith("GET") and key:
        if key in db:
            response = db[key]
        else:
            response = ""
    elif data.startswith("SET") and key:
        try:
          value = parts[2]
        except IndexError:
          value = None

        if value:
            db[key] = value
            response = "OK"
        else:
            response = "N/A"
    elif data.startswith("DEL"):
        if key:
            if key in db:
                del db[key]
                response = "1"
            else:
                response = "0"
        else:
            response = "N/A"
    elif data.startswith("INCR"):
        if key:
            if key in db:
                try:
                    existing_value = int(db[key])
                    new_value = str(existing_value + 1)
                    db[key] = new_value
                    response = new_value
                except ValueError:
                    response = "ERR value is not an integer or out of range"
            else:
                db[key] = "1"
                response = "1"
        else:
          response = "N/A"
    elif data.startswith("QUIT"):
        client.close()
        del sockets[sockets.index(client)]
        return
    else:
        response = "N/A"

    try:
      client.send(str.encode(response + "\n"))
    except BrokenPipeError:
        client.close()
        del sockets[sockets.index(client)]

if __name__ == '__main__':
    server_address = ('localhost', 3000)
    print('starting up on', server_address)

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setblocking(0)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(server_address)
    server.listen(5)

    sockets.append(server)

    while True:
        readable, writable, exceptional = select.select(sockets, [], [])
        for socket in readable:
            if socket == server:
                client, client_address = server.accept()
                client.setblocking(0)
                handle_client(client)
            else:
                handle_request(socket)
