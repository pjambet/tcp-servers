package main;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.nio.channels.ServerSocketChannel;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Iterator;
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
        HashMap<String, String> db = new HashMap<>();

        //noinspection InfiniteLoopStatement
        while (true) {
            selector.select();
            Set<SelectionKey> selectedKeys = selector.selectedKeys();
            Iterator<SelectionKey> iterator = selectedKeys.iterator();

            while (iterator.hasNext()) {
                SelectionKey key = iterator.next();

                if (key.isAcceptable()) {
                    register(selector, serverSocket);
                }

                if (key.isReadable()) {
                    answerWithEcho(key, db);
                }

                iterator.remove();
            }
        }
    }

    public static void zeroBuffersArray(ByteBuffer buf) {
        Arrays.fill(buf.array(), (byte)0);
        buf.clear();
    }

    private static void answerWithEcho(SelectionKey selectionKey, HashMap<String, String> db) {
        ByteBuffer buffer = ByteBuffer.allocate(256);
        SocketChannel client = (SocketChannel) selectionKey.channel();
        try {
            client.read(buffer);
            String request = new String(buffer.array()).trim();

            if (request.equals("foo de fafa") || request.equals("")) {
                client.close();
                System.out.println("Not accepting client messages anymore");
            } else if (request.startsWith("GET")) {
                String[] parts = request.split(" ");
                String responseString = db.getOrDefault(parts[1], "");
                responseString += "\n";
                ByteBuffer response = ByteBuffer.wrap(responseString.getBytes(StandardCharsets.UTF_8));
                client.write(response);
            } else if (request.startsWith("SET")) {
                String[] parts = request.split(" ");
                String responseString;
                if (parts.length >= 3) {
                    responseString = "OK\n";
                    String key = parts[1];
                    String value = parts[2];
                    db.put(key, value);
                } else {
                    responseString = "ERROR\n";
                }
                ByteBuffer response = ByteBuffer.wrap(responseString.getBytes(StandardCharsets.UTF_8));
                client.write(response);
            } else {
                buffer.flip();
                client.write(buffer);
                buffer.clear();
            }
        } catch (IOException e) {
            System.err.println("Error handling client " + client + ", " + e.getMessage());
            if (client.isOpen()) {
                try {
                    client.close();
                } catch (IOException e2) {
                    System.err.println("Another error ... " + e2.getMessage());
                }
            }
        }
    }
    private static void register(Selector selector, ServerSocketChannel serverSocket) throws IOException {
        SocketChannel client = serverSocket.accept();
        client.configureBlocking(false);
        client.register(selector, SelectionKey.OP_READ);
    }
}
