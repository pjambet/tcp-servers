package main

import org.slf4j.Logger
import org.slf4j.LoggerFactory
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.Channel.Factory.RENDEZVOUS
import kotlinx.coroutines.channels.Channel.Factory.UNLIMITED
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.Socket

suspend fun runServer(opChannel: Channel<Operation>) = coroutineScope {
    val coroutineExceptionHandler = CoroutineExceptionHandler { _, exception ->
        log.error("Handle $exception in CoroutineExceptionHandler")
    }
    launch(Dispatchers.IO) {
        val server = ServerSocket(3000)
        log.info("Listening on port 3000")

        while(true) {
            val client = server.accept()
            log.info("Starting handler for: $client")
            supervisorScope {
                launch { handleClient(client, opChannel) }
            }
            log.info("Launched")
        }
    }
}

suspend fun handleClient(client: Socket, channel: Channel<Operation>) {
    log.info("Handling client: $client")
    while (true) {
        val output = PrintWriter(client.getOutputStream(), true)
        val input = BufferedReader(InputStreamReader(client.inputStream)).readLine()

        if (input == "STOP") {
            client.close()
        } else if (input.startsWith("GET")) {
            var key: String
            try {
                key = input.split(" ")[1]//.getOrNull(1)
            } catch(e: Exception) {
//                log.error("ERROR, boooo", e)
                throw e
            }
            if (key != null) {
                val chan = Channel<String?>()
                channel.send(Operation(key, null, chan))
                val result = chan.receive() ?: "N/A"
                output.println(result + "\n")
            } else {
                output.println("N/A\n")
            }
        } else if (input.startsWith("SET")) {
            val key = input.split(" ").getOrNull(1)
            val value = input.split(" ").getOrNull(2)
            if (key != null && value != null) {
                val chan = Channel<String?>(RENDEZVOUS)
                channel.send(Operation(key, value, chan))
                output.println("OK\n")
            } else {
                output.println("N/A\n")
            }
        }
    }
}

data class Operation(val key: String, val value: String?, val chan: Channel<String?>)

val log: Logger = LoggerFactory.getLogger("Coroutines")

fun main() {
    val opChannel = Channel<Operation>(UNLIMITED)
    val state = mutableMapOf<String, String>()

    GlobalScope.launch {
        log.info("Starting op loop")
        while(true) {
            val op = opChannel.receive()
            if (op.value == null) {
                log.debug("GET request")
                op.chan.send(state[op.key])
                op.chan.close()
            } else {
                log.debug("SET request")
                state[op.key] = op.value
                op.chan.close()
            }
        }
    }
    runBlocking {
        runServer(opChannel)
    }
}