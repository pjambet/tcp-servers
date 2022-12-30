package main

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
)

const MIN = 1
const MAX = 100

type Command int

const (
	Get  Command = iota + 1 // 1
	Set                     // 2
	Incr                    // 3
	Del                     // 4
)

type commandMessage struct {
	commandName     Command
	key             string
	value           string
	responseChannel chan string
}

func handleConnection(commandChannel chan commandMessage, client net.Conn) {
	defer client.Close()

	for {
		netData, err := bufio.NewReader(client).ReadString('\n')
		if err != nil {
			fmt.Println("error reading:", err)
			return
		}

		var response string
		commandString := strings.TrimSpace(netData)
		parts := strings.Split(commandString, " ")
		command := parts[0]

		switch command {
		case "STOP", "QUIT":
			return
		case "GET":
			if len(parts) > 1 {
				key := parts[1]
				commandMessage := commandMessage{
					commandName:     Get,
					key:             key,
					responseChannel: make(chan string)}

				commandChannel <- commandMessage
				response = <-commandMessage.responseChannel
			} else {
				response = "ERR wrong number of arguments for 'get' command"
			}
		case "SET":
			if len(parts) > 2 {
				key := parts[1]
				value := parts[2]
				commandMessage := commandMessage{
					commandName:     Set,
					key:             key,
					value:           value,
					responseChannel: make(chan string)}

				commandChannel <- commandMessage
				response = <-commandMessage.responseChannel
			} else {
				response = "ERR wrong number of arguments for 'set' command"
			}
		case "INCR":
			if len(parts) > 1 {
				key := parts[1]
				commandMessage := commandMessage{
					commandName:     Incr,
					key:             key,
					responseChannel: make(chan string)}

				commandChannel <- commandMessage
				response = <-commandMessage.responseChannel
			} else {
				response = "ERR wrong number of arguments for 'incr' command"
			}
		case "DEL":
			key := parts[1]
			commandMessage := commandMessage{
				commandName:     Del,
				key:             key,
				responseChannel: make(chan string)}

			commandChannel <- commandMessage
			response = <-commandMessage.responseChannel
		default:
			response = "ERR unknown command"
		}

		client.Write([]byte(response + "\n"))
	}
}

func handleDB(commandChannel chan commandMessage) {
	db := make(map[string]string)

	for {
		select {
		case command := <-commandChannel:
			switch command.commandName {
			case Get:
				command.responseChannel <- db[command.key]
			case Set:
				db[command.key] = command.value
				command.responseChannel <- "OK"
			case Incr:
				value, ok := db[command.key]
				var response string

				if ok {
					intValue, err := strconv.Atoi(value)
					if err != nil {
						response = "ERR value is not an integer or out of range"
					} else {
						response = strconv.Itoa(intValue + 1)
						db[command.key] = response
					}
				} else {
					response = "1"
					db[command.key] = response
				}
				command.responseChannel <- response
			case Del:
				_, ok := db[command.key]
				var response string

				if ok {
					delete(db, command.key)
					response = "1"
				} else {
					response = "0"
				}
				command.responseChannel <- response
			}
		}
	}
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

	commandChannel := make(chan commandMessage)

	go handleDB(commandChannel)

	for {
		client, err := server.Accept()
		if err != nil {
			fmt.Println(err)
			return
		}
		go handleConnection(commandChannel, client)
	}
}
