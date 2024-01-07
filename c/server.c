#include <stdio.h>     // For printf
#include <netdb.h>     // For bind, listen, AF_INET, SOCK_STREAM, socklen_t, sockaddr_in, INADDR_ANY
#include <stdlib.h>    // For exit
#include <string.h>    // For bzero
#include <unistd.h>    // For close & write
#include <errno.h>     // For errno, duh!
#include <arpa/inet.h> // For inet_ntop
#include <stdbool.h>
#include <assert.h>

#define MAX 80
#define PORT 3000
#define SA struct sockaddr

typedef struct ht ht;

typedef struct
{
  const char *key; // key is NULL if this slot is empty
  void *value;
} ht_entry;

// Hash table structure: create with ht_create, free with ht_destroy.
struct ht
{
  ht_entry *entries; // hash slots
  size_t capacity;   // size of _entries array
  size_t length;     // number of items in hash table
};

#define INITIAL_CAPACITY 16 // must not be zero

// Create hash table and return pointer to it, or NULL if out of memory.
ht *ht_create(void)
{
  // Allocate space for hash table struct.
  ht *table = malloc(sizeof(ht));
  if (table == NULL)
  {
    return NULL;
  }
  table->length = 0;
  table->capacity = INITIAL_CAPACITY;

  // Allocate (zero'd) space for entry buckets.
  table->entries = calloc(table->capacity, sizeof(ht_entry));
  if (table->entries == NULL)
  {
    free(table); // error, free table before we return!
    return NULL;
  }
  return table;
}

// Free memory allocated for hash table, including allocated keys.
void ht_destroy(ht *table)
{
  // First free allocated keys.
  for (size_t i = 0; i < table->capacity; i++)
  {
    free((void *)table->entries[i].key);
  }

  // Then free entries array and table itself.
  free(table->entries);
  free(table);
}

#define FNV_OFFSET 14695981039346656037UL
#define FNV_PRIME 1099511628211UL

// Return 64-bit FNV-1a hash for key (NUL-terminated). See description:
// https://en.wikipedia.org/wiki/Fowler–Noll–Vo_hash_function
static uint64_t hash_key(const char *key)
{
  uint64_t hash = FNV_OFFSET;
  for (const char *p = key; *p; p++)
  {
    hash ^= (uint64_t)(unsigned char)(*p);
    hash *= FNV_PRIME;
  }
  return hash;
}

// Get item with given key (NUL-terminated) from hash table. Return
// value (which was set with ht_set), or NULL if key not found.
void *ht_get(ht *table, const char *key)
{
  // AND hash with capacity-1 to ensure it's within entries array.
  uint64_t hash = hash_key(key);
  size_t index = (size_t)(hash & (uint64_t)(table->capacity - 1));

  // Loop till we find an empty entry.
  while (table->entries[index].key != NULL)
  {
    if (strcmp(key, table->entries[index].key) == 0)
    {
      // Found key, return value.
      return table->entries[index].value;
    }
    // Key wasn't in this slot, move to next (linear probing).
    index++;
    if (index >= table->capacity)
    {
      // At end of entries array, wrap around.
      index = 0;
    }
  }
  return NULL;
}

static const char *ht_set_entry(ht_entry *entries, size_t capacity,
                                const char *key, void *value, size_t *plength)
{
  // AND hash with capacity-1 to ensure it's within entries array.
  uint64_t hash = hash_key(key);
  size_t index = (size_t)(hash & (uint64_t)(capacity - 1));

  // Loop till we find an empty entry.
  while (entries[index].key != NULL)
  {
    if (strcmp(key, entries[index].key) == 0)
    {
      // Found key (it already exists), update value.
      entries[index].value = value;
      return entries[index].key;
    }
    // Key wasn't in this slot, move to next (linear probing).
    index++;
    if (index >= capacity)
    {
      // At end of entries array, wrap around.
      index = 0;
    }
  }

  // Didn't find key, allocate+copy if needed, then insert it.
  if (plength != NULL)
  {
    key = strdup(key);
    if (key == NULL)
    {
      return NULL;
    }
    (*plength)++;
  }
  entries[index].key = (char *)key;
  entries[index].value = value;
  return key;
}

// Expand hash table to twice its current size. Return true on success,
// false if out of memory.
static bool ht_expand(ht *table)
{
  // Allocate new entries array.
  size_t new_capacity = table->capacity * 2;
  if (new_capacity < table->capacity)
  {
    return false; // overflow (capacity would be too big)
  }
  ht_entry *new_entries = calloc(new_capacity, sizeof(ht_entry));
  if (new_entries == NULL)
  {
    return false;
  }

  // Iterate entries, move all non-empty ones to new table's entries.
  for (size_t i = 0; i < table->capacity; i++)
  {
    ht_entry entry = table->entries[i];
    if (entry.key != NULL)
    {
      ht_set_entry(new_entries, new_capacity, entry.key,
                   entry.value, NULL);
    }
  }

  // Free old entries array and update this table's details.
  free(table->entries);
  table->entries = new_entries;
  table->capacity = new_capacity;
  return true;
}

// Set item with given key (NUL-terminated) to value (which must not
// be NULL). If not already present in table, key is copied to newly
// allocated memory (keys are freed automatically when ht_destroy is
// called). Return address of copied key, or NULL if out of memory.
const char *ht_set(ht *table, const char *key, void *value)
{
  assert(value != NULL);
  if (value == NULL)
  {
    return NULL;
  }

  // If length will exceed half of current capacity, expand it.
  if (table->length >= table->capacity / 2)
  {
    if (!ht_expand(table))
    {
      return NULL;
    }
  }

  // Set entry and update length.
  return ht_set_entry(table->entries, table->capacity, key, value,
                      &table->length);
}

// Return number of items in hash table.
size_t ht_length(ht *table)
{
  return table->length;
}

// Hash table iterator: create with ht_iterator, iterate with ht_next.
typedef struct
{
  const char *key; // current key
  void *value;     // current value

  // Don't use these fields directly.
  ht *_table;    // reference to hash table being iterated
  size_t _index; // current index into ht._entries
} hti;

// Return new hash table iterator (for use with ht_next).
hti ht_iterator(ht *table)
{
  hti it;
  it._table = table;
  it._index = 0;
  return it;
}

// Move iterator to next item in hash table, update iterator's key
// and value to current item, and return true. If there are no more
// items, return false. Don't call ht_set during iteration.
bool ht_next(hti *it)
{
  // Loop till we've hit end of entries array.
  ht *table = it->_table;
  while (it->_index < table->capacity)
  {
    size_t i = it->_index;
    it->_index++;
    if (table->entries[i].key != NULL)
    {
      // Found next non-empty item, update iterator key and value.
      ht_entry entry = table->entries[i];
      it->key = entry.key;
      it->value = entry.value;
      return true;
    }
  }
  return false;
}

struct string_header
{
  long len;
  char buf[];
};

typedef char *string;

// static inline int sdsHdrSize(char type)
int stringHeaderSize()
{
  return sizeof(struct string_header);
}

string stringnewlen(const void *init, size_t initlen)
{
  struct string_header *sh;

  sh = malloc(sizeof(struct string_header) + initlen + 1);
  if (sh == NULL)
    return NULL;
  sh->len = initlen;
  // sh->free = 0;
  if (initlen)
  {
    if (init)
      memcpy(sh->buf, init, initlen);
    else
      memset(sh->buf, 0, initlen);
  }
  sh->buf[initlen] = '\0';
  return (char *)sh->buf;
}

void sdsfree(string s)
{
  if (s == NULL)
    return;
  free((char *)s - stringHeaderSize());
}

unsigned long hash(unsigned char *str)
{
  unsigned long hash = 5381;
  int c;

  while ((c = *str++))
  {
    hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
  }

  return hash;
}

void exit_nomem(void)
{
  fprintf(stderr, "out of memory\n");
  exit(1);
}

int main()
{

  ht *counts = ht_create();
  if (counts == NULL)
  {
    exit_nomem();
  }

  // Read next word from stdin (at most 100 chars long).
  char word[101];
  while (scanf("%100s", word) != EOF)
  {
    // Look up word.
    void *value = ht_get(counts, word);
    if (value != NULL)
    {
      // Already exists, increment int that value points to.
      int *pcount = (int *)value;
      (*pcount)++;
      continue;
    }

    // Word not found, allocate space for new int and set to 1.
    int *pcount = malloc(sizeof(int));
    if (pcount == NULL)
    {
      exit_nomem();
    }
    *pcount = 1;
    if (ht_set(counts, word, pcount) == NULL)
    {
      exit_nomem();
    }
  }

  // Print out words and frequencies, freeing values as we go.
  hti it = ht_iterator(counts);
  while (ht_next(&it))
  {
    printf("%s %d\n", it.key, *(int *)it.value);
    free(it.value);
  }

  // Show the number of unique words.
  printf("%d\n", (int)ht_length(counts));

  ht_destroy(counts);

  socklen_t client_address_length;
  int server_socket_file_descriptor, client_socket_file_descriptor;
  struct sockaddr_in server_address, client_address;

  // socket create and verification
  server_socket_file_descriptor = socket(AF_INET, SOCK_STREAM, 0);
  if (server_socket_file_descriptor == -1)
  {
    printf("socket creation failed...\n");
    exit(0);
  }
  else
  {
    printf("Socket successfully created..\n");
  }
  bzero(&server_address, sizeof(server_address));

  // assign IP, PORT
  server_address.sin_family = AF_INET;
  server_address.sin_addr.s_addr = htonl(INADDR_ANY);
  server_address.sin_port = htons(PORT);

  // Binding newly created socket to given IP and verification
  if ((bind(server_socket_file_descriptor, (SA *)&server_address, sizeof(server_address))) != 0)
  {
    printf("socket bind failed... : %d, %d\n", server_socket_file_descriptor, errno);
    exit(0);
  }
  else
  {
    printf("Socket successfully bound..\n");
  }

  // Now server is ready to listen and verification
  if ((listen(server_socket_file_descriptor, 5)) != 0)
  {
    printf("Listen failed...\n");
    exit(0);
  }
  else
  {
    printf("Server listening..\n");
  }
  client_address_length = sizeof(client_address);

  // Accept the data packet from client and verification
  client_socket_file_descriptor = accept(server_socket_file_descriptor, (SA *)&client_address, &client_address_length);
  if (client_socket_file_descriptor < 0)
  {
    printf("server accept failed: %d,%d...\n", client_socket_file_descriptor, errno);
    exit(0);
  }
  else
  {
    printf("server accept the client...\n");
    char human_readable_address[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &client_address.sin_addr, human_readable_address, sizeof(human_readable_address));
    printf("Client address: %s\n", human_readable_address);
  }

  char message_buffer[MAX];
  read(client_socket_file_descriptor, message_buffer, sizeof(message_buffer));
  printf("From Client: %s\n", message_buffer);
  bzero(message_buffer, MAX);

  strcpy(message_buffer, "Hello, this is Server!");
  write(client_socket_file_descriptor, message_buffer, sizeof(message_buffer));

  // After chatting close the socket
  printf("Closing server_socket_file_descriptor\n");
  close(server_socket_file_descriptor);
}