// Inspired from: https://riptutorial.com/node-js/example/22405/a-simple-tcp-server
const Net = require('net');
const port = process.argv[2];
const db = new Map();

const server = new Net.Server();
server.listen(port, function() {
    console.log(`Server listening for connection requests on socket localhost:${port}.`);
});

server.on('connection', function(socket) {
    console.log('A new connection has been established.');
    let response = '';

    socket.on('data', function(chunk) {
        let request = chunk.toString();
        console.log(`Data received from client: ${request}.`);
        if (request.startsWith('GET')) {
            let parts = request.split(' ');
            let key = parts[1].trim();
            if (key) {
                response = db.get(key) || '';
                response += '\n';
            } else {
                response = 'N/A\n';
            }
        } else if (request.startsWith('SET')) {
            let parts = request.split(' ');
            console.log(parts);
            let key = parts[1].trim();
            let value = parts[2].trim();

            if (key && value) {
                db.set(key, value);
                response = 'OK\n';
            } else {
                response = 'N/A\n';
            }
        } else if (request.startsWith("QUIT")) {
            socket.close();
        } else {
            response = 'N/A\n';
        }
        socket.write(response);
    });

    socket.on('end', function() {
        console.log('Closing connection with the client');
    });

    socket.on('error', function(err) {
        console.log(`Error: ${err}`);
    });
});
