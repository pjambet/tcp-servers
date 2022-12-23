CC=gcc 
CFLAGS=-Wall

all: server
server: server.o
server.o: server.c

clean:
	- rm -f server server.o
run: server
	./server
