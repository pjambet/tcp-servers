package main

import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.Channel.Factory.UNLIMITED
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.Socket

suspend fun runServer(opChannel: Channel<Operation>) = coroutineScope {
    launch(Dispatchers.Default) {
        val server = ServerSocket(3000)
        println("Listening on port 3000")

        while(true) {
            val client = server.accept()
            println("Sending to channel: $client")
            launch { handleClient(client, opChannel) }
        }
    }
}

suspend fun handleClient(client: Socket, channel: Channel<Operation>) = coroutineScope {
    while (true) {
        val output = PrintWriter(client.getOutputStream(), true)
        val input = BufferedReader(InputStreamReader(client.inputStream)).readLine()

        if (input == "STOP") {
            client.close()
        } else if (input.startsWith("GET")) {
            val key = input.split(" ")[1]
            if (key != null) {
                val chan = Channel<String?>()
                channel.send(Operation(key, null, chan))
                val result = chan.receive() ?: "N/A"
                output.println(result + "\n")
            } else {
                output.println("N/A\n")
            }
        } else if (input.startsWith("SET")) {
            val key = input.split(" ")[1]
            val value = input.split(" ")[2]
            if (key != null && value != null) {
                val chan = Channel<String?>()
                channel.send(Operation(key, value, chan))
                output.println("OK\n")
            } else {
                output.println("N/A\n")
            }
        }
    }
}

data class Operation(val key: String, val value: String?, val chan: Channel<String?>)

fun main() {
    val opChannel = Channel<Operation>(UNLIMITED)
    val state = mutableMapOf<String, String>()

    GlobalScope.launch {
        while(true) {
            val op = opChannel.receive()
            if (op.value == null) {
                // GET
                op.chan.send(state[op.key])
                op.chan.close()
            } else {
                // SET
                state[op.key] = op.value
                op.chan.close()
            }
        }
    }
    runBlocking {
        runServer(opChannel)
    }
}