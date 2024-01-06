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

abstract sealed class Operation(key: String, channel: Channel<String?>)
data class GetOperation(val key: String, val channel: Channel<String?>) : Operation(key, channel)
data class SetOperation(val key: String, val value: String, val channel: Channel<String?>) : Operation(key, channel)
data class DelOperation(val key: String, val channel: Channel<String?>) : Operation(key, channel)
data class IncrOperation(val key: String, val channel: Channel<String?>) : Operation(key, channel)

suspend fun runServer(opChannel: Channel<Operation>) = coroutineScope {
    launch(Dispatchers.IO) {
        val server = ServerSocket(3000)
        log.info("Listening on port 3000")

        while(true) {
            val client = server.accept()
            log.info("Starting handler for: $client")
            launch(Dispatchers.IO) {
                try {
                    handleClient(client, opChannel)
                } catch (t: Throwable) {
                    log.error("Error handling client", t)
                    client.close()
                }
            }
            log.info("Launched")
        }
    }
}

suspend fun handleClient(client: Socket, channel: Channel<Operation>) {
    log.info("Handling client: $client")
    withContext(Dispatchers.IO) {
        while (true) {
            val output = PrintWriter(client.getOutputStream(), true)
            val input = BufferedReader(InputStreamReader(client.inputStream)).readLine()
            if (input == null) {
                client.close()
                return@withContext
            }

            if (input.startsWith("STOP") || input.startsWith("QUIT")) {
                client.close()
                return@withContext
            } else if (input.startsWith("GET")) {
                var key: String?
                try {
                    key = input.split(" ").getOrNull(1)
                } catch (e: Exception) {
                    throw e
                }
                if (key != null) {
                    val chan = Channel<String?>()
                    channel.send(GetOperation(key, chan))
                    val result = chan.receive() ?: ""
                    output.println(result)
                } else {
                    output.println("")
                }
            } else if (input.startsWith("SET")) {
                val key = input.split(" ").getOrNull(1)
                val value = input.split(" ").getOrNull(2)
                if (key != null && value != null) {
                    val chan = Channel<String?>(RENDEZVOUS)
                    channel.send(SetOperation(key, value, chan))
                    output.println("OK")
                } else {
                    output.println("")
                }
            } else if (input.startsWith("DEL")) {
                val key = input.split(" ").getOrNull(1)
                if (key != null) {
                    val chan = Channel<String?>(RENDEZVOUS)
                    channel.send(DelOperation(key, chan))
                    val result = chan.receive() ?: ""
                    output.println(result)
                } else {
                    output.println("")
                }
            } else if (input.startsWith("INCR")) {
                val key = input.split(" ").getOrNull(1)
                if (key != null) {
                    val chan = Channel<String?>(RENDEZVOUS)
                    channel.send(IncrOperation(key, chan))
                    val result = chan.receive() ?: ""
                    output.println(result)
                } else {
                    output.println("")
                }
            } else if (input.startsWith("RAISE")) {
                throw Throwable("foo de fafa")
            }
        }
    }
}

val log: Logger = LoggerFactory.getLogger("Coroutines")

fun main() {
    val opChannel = Channel<Operation>(UNLIMITED)
    val state = mutableMapOf<String, String>()

    GlobalScope.launch {
        while(true) {
            val op = opChannel.receive()
            when (op) {
                is GetOperation -> {
                    op.channel.send(state[op.key])
                    op.channel.close()
                }
                is SetOperation -> {
                    state[op.key] = op.value
                    op.channel.close()
                }
                is DelOperation -> {
                    val removed = state.remove(op.key)
                    val response = if (removed == null) "0" else "1"
                    op.channel.send(response)
                    op.channel.close()
                }
                is IncrOperation -> {
                    val existingValue = state[op.key]
                    val response = if (existingValue != null) {
                        val existingInt = existingValue.toIntOrNull()
                        if (existingInt == null) {
                            "ERR value is not an integer or out of range"
                        } else {
                            val newValue = (existingInt + 1).toString()
                            state[op.key] = newValue
                            newValue
                        }
                    } else {
                        state[op.key] = "1"
                        "1"
                    }
                    op.channel.send(response)
                    op.channel.close()
                }
            }
        }
    }
    runBlocking {
        runServer(opChannel)
    }
}