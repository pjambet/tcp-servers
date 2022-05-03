import select
import socket
import sys

sockets = []
db = {}

def handle_client(client):
    sockets.append(client)

def handle_request(client):
    print("Request from client")
    data = client.recv(1024).decode("utf-8").strip()
    parts = data.split(" ")
    print("data", data)
    key = parts[1]
    response = None
    print("parts: ", parts)
    print("db: ", db)
    
    if data.startswith("GET") and key:
        if key in db:
            response = db[key] + "\n"
        else:
            response = ":(\n"

    elif data.startswith("SET") and key:
        value = parts[2]
        print("Setting: ", key, value)
        if value:
            db[key] = value
            response = "OK\n"
        else:
            response = ":(\n"
    else:
        response = "N/A\n"

    client.send(str.encode(response))

if __name__ == '__main__':
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setblocking(0)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_address = ('localhost', 3000)
    print('starting up on', server_address)
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
