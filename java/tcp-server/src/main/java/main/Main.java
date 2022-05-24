package main;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.nio.channels.ServerSocketChannel;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Set;

public class Main {
    public static void main(String[] args) throws IOException {
        Selector selector = Selector.open();
        int port;
        if (args.length < 1) {
            port = 3000;
        } else {
            port = Integer.parseInt(args[0]);
        }
        ServerSocketChannel serverSocket = ServerSocketChannel.open();
        InetSocketAddress address = new InetSocketAddress(port);
        serverSocket.socket().bind(address);
        serverSocket.configureBlocking(false);
        serverSocket.register(selector, SelectionKey.OP_ACCEPT);

        System.out.println("Started on " + address);

        ByteBuffer buffer = ByteBuffer.allocate(256);

        HashMap<String, String> db = new HashMap<>();
        db.put("123", "456");

        //noinspection InfiniteLoopStatement
        while (true) {
            selector.select();
            Set<SelectionKey> selectedKeys = selector.selectedKeys();

            for (SelectionKey key : selectedKeys) {
                if (key.isAcceptable()) {
                    register(selector, serverSocket);
                }

                if (key.isReadable()) {
                    answerWithEcho(buffer, key, db);
                }
                selectedKeys.remove(key);
            }
        }
    }

    private static void answerWithEcho(ByteBuffer buffer, SelectionKey key, HashMap<String, String> db) throws IOException {
        SocketChannel client = (SocketChannel) key.channel();
        client.read(buffer);
        String request = new String(buffer.array()).trim();

        if (request.equals("foo de fafa")) {
            client.close();
            System.out.println("Not accepting client messages anymore");
        } else if (request.startsWith("GET")) {
            String[] parts = request.split(" ");
            buffer.flip();
            String responseString = db.getOrDefault(parts[1], "");
            responseString += "\n";
            ByteBuffer response = ByteBuffer.wrap(responseString.getBytes(StandardCharsets.UTF_8));
            client.write(response);
            buffer.clear();
        } else {
            buffer.flip();
            client.write(buffer);
            buffer.clear();
        }
    }
    private static void register(Selector selector, ServerSocketChannel serverSocket) throws IOException {
        SocketChannel client = serverSocket.accept();
        client.configureBlocking(false);
        client.register(selector, SelectionKey.OP_READ);
    }
}
