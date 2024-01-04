// Inspired from: https://riptutorial.com/node-js/example/22405/a-simple-tcp-server
const Net = require('net');
const port = process.argv[2];
const db = new Map();

const server = new Net.Server();

function extractKey(request) {
  let parts = request.split(' ');

  return parts[1] && parts[1].trim();
}

function extractKeyAndValue(request) {
  let parts = request.split(' ');
  key = parts[1] && parts[1].trim();
  value = parts[2] && parts[2].trim();

  return [key, value];
}

server.listen(port, function () {
  console.log(`Server listening for connection requests on socket localhost:${port}.`);
});

server.on('connection', function (socket) {
  let response = '';

  socket.on('data', function (chunk) {
    let request = chunk.toString();

    if (request.startsWith('GET')) {
      let key = extractKey(request);

      if (key) {
        response = db.get(key) || '';
        response += '';
      } else {
        response = 'N/A';
      }
    } else if (request.startsWith('SET')) {
      let [key, value] = extractKeyAndValue(request)

      if (key && value) {
        db.set(key, value);
        response = 'OK';
      } else {
        response = 'N/A';
      }
    } else if (request.startsWith("DEL")) {
      let key = extractKey(request);

      if (db.delete(key)) {
        response = "1"
      } else {
        response = "0"
      }
    } else if (request.startsWith("INCR")) {
      let key = extractKey(request);
      let existing = db.get(key);

      if (existing === undefined) {
        db.set(key, "1")
        response = "1"
      } else {
        let existingNumber = Number(existing)
        if (isNaN(existingNumber)) {
          response = "ERR value is not an integer or out of range"
        } else {
          let existingString = String(existingNumber + 1)
          db.set(key, existingString)
          response = existingString
        }
      }
    } else if (request.startsWith("QUIT")) {
      socket.destroy()
      return
    } else {
      response = 'N/A';
    }
    socket.write(response + "\n");
  });

  socket.on('end', function () {
    console.log('Closing connection with the client');
  });

  socket.on('error', function (err) {
    console.log(`Error: ${err}`);
  });
});
