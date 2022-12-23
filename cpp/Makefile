CC=g++
CPPFLAGS=-Wall

all: server
server: server.o
server.o: server.cpp

# server: server.o
# 	$(CC) $(CPPFLAGS) -o server server.o

# server.o: server.cpp
# 	$(CC) $(CPPFLAGS) -c server.cpp

clean:
	rm server.o server
run: server
	./server