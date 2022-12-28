package main

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"strings"
)

const MIN = 1
const MAX = 100

type Command int

const (
	Get Command = iota + 1 // 1
	Set                    // 2
)

type commandMessage struct {
	commandName     Command
	key             string
	value           string
	responseChannel chan string
}

func handleConnection(commandChannel chan commandMessage, client net.Conn) {
	for {
		netData, err := bufio.NewReader(client).ReadString('\n')
		if err != nil {
			fmt.Println("error reading:", err)
			return
		}

		commandString := strings.TrimSpace(netData)
		if commandString == "STOP" || commandString == "QUIT" {
			break
		} else if strings.HasPrefix(commandString, "GET") {
			parts := strings.Split(commandString, " ")
			if len(parts) > 1 {
				key := parts[1]
				command := commandMessage{
					commandName:     Get,
					key:             key,
					responseChannel: make(chan string)}
				commandChannel <- command
				res := <-command.responseChannel
				client.Write([]byte(res + "\n"))
			}
		} else if strings.HasPrefix(commandString, "SET") {
			parts := strings.Split(commandString, " ")
			if len(parts) > 2 {
				key := parts[1]
				value := parts[2]
				command := commandMessage{
					commandName:     Set,
					key:             key,
					value:           value,
					responseChannel: make(chan string)}
				commandChannel <- command
				res := <-command.responseChannel
				client.Write([]byte(res + "\n"))
			}
		}
	}
	client.Close()
}

func main() {
	arguments := os.Args
	if len(arguments) == 1 {
		fmt.Println("Please provide a port number!")
		return
	}

	PORT := ":" + arguments[1]
	server, err := net.Listen("tcp4", PORT)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer server.Close()

	db := make(map[string]string)
	commandChannel := make(chan commandMessage)

	go func() {
		for {
			select {
			case command := <-commandChannel:
				switch command.commandName {
				case Get:
					command.responseChannel <- db[command.key]
				case Set:
					db[command.key] = command.value
					command.responseChannel <- "OK"
				}
			}
		}
	}()

	for {
		client, err := server.Accept()
		if err != nil {
			fmt.Println(err)
			return
		}
		go handleConnection(commandChannel, client)
	}
}
