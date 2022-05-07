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

type op struct {
	key   string
	value string
	resp  chan string
}

func handleConnection(channel chan op, c net.Conn) {
	// fmt.Printf("Serving %s\n", c.RemoteAddr().String())
	for {
		netData, err := bufio.NewReader(c).ReadString('\n')
		if err != nil {
			fmt.Println("error reading:", err)
			return
		}

		temp := strings.TrimSpace(netData)
		// fmt.Println(temp)
		if temp == "STOP" || temp == "QUIT" {
			break
		} else if strings.HasPrefix(temp, "GET") {
			parts := strings.Split(temp, " ")
			if len(parts) > 1 {
				key := parts[1]
				op := op{
					key:  key,
					resp: make(chan string)}
				channel <- op
				res := <-op.resp
				c.Write([]byte(res + "\n"))
			}
		} else if strings.HasPrefix(temp, "SET") {
			parts := strings.Split(temp, " ")
			if len(parts) > 2 {
				key := parts[1]
				value := parts[2]
				op := op{
					key:   key,
					value: value,
					resp:  make(chan string)}
				channel <- op
				res := <-op.resp
				c.Write([]byte(res + "\n"))
			}
		}
	}
	c.Close()
}

func main() {
	arguments := os.Args
	if len(arguments) == 1 {
		fmt.Println("Please provide a port number!")
		return
	}

	PORT := ":" + arguments[1]
	l, err := net.Listen("tcp4", PORT)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer l.Close()

	m := make(map[string]string)
	channel := make(chan op)

	go func() {
		for {
			select {
			case res := <-channel:
				if len(res.value) > 0 {
					m[res.key] = res.value
					res.resp <- "OK"
				} else {
					// fmt.Println("map:", m)
					res.resp <- m[res.key]
				}
			}
		}
	}()

	for {
		c, err := l.Accept()
		if err != nil {
			fmt.Println(err)
			return
		}
		go handleConnection(channel, c)
	}
}
