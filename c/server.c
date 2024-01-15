#include <stdio.h>     // For printf
#include <netdb.h>     // For bind, listen, AF_INET, SOCK_STREAM, socklen_t, sockaddr_in, INADDR_ANY
#include <stdlib.h>    // For exit
#include <string.h>    // For bzero
#include <unistd.h>    // For close & write
#include <errno.h>     // For errno, duh!
#include <arpa/inet.h> // For inet_ntop
#include <stdbool.h>
#include <assert.h>
#include <sys/select.h>

#define MAX 80
#define PORT 3000
#define SA struct sockaddr

typedef struct ht ht;

typedef struct
{
  const char *key; // key is NULL if this slot is empty
  const char *value;
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
    if (table->entries[i].key != NULL)
    {
      printf("free-ing key: '%p'\n", table->entries[i].key);
      free((void *)table->entries[i].key);
    }
    if (table->entries[i].value != NULL)
    {
      printf("free-ing value: '%p'\n", table->entries[i].value);
      free((void *)table->entries[i].value);
    }
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

static size_t ht_index(size_t capacity, const char *key)
{
  // AND hash with capacity-1 to ensure it's within entries array.
  uint64_t hash = hash_key(key);
  return (size_t)(hash & (uint64_t)(capacity - 1));
}

// Get item with given key (NUL-terminated) from hash table. Return
// value (which was set with ht_set), or NULL if key not found.
const char *ht_get(ht *table, const char *key)
{
  size_t index = ht_index(table->capacity, key);

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
                                const char *key, const char *value, size_t *plength)
{
  size_t index = ht_index(capacity, key);

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
const char *ht_set(ht *table, const char *key, const char *value)
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

void ht_fill_gap(ht *table, size_t starting_index)
{
  size_t free_slot = starting_index;
  size_t current_index = (starting_index + 1) % table->capacity;
  while (table->entries[current_index].key != NULL)
  {
    // i = free_slot
    // j = current_index
    // k = entry_real_index
    ht_entry entry = table->entries[current_index];
    size_t entry_real_index = ht_index(table->capacity, entry.key);
    printf("current_index: %zu\n", current_index);

    // For all records in a cluster, there must be no vacant slots between their
    // natural hash position and their current position (else lookups will
    // terminate before finding the record). At this point in the pseudocode,
    // free_slot is a vacant slot that might be invalidating this property for
    // subsequent records in the cluster. current_index is such a subsequent
    // record. entry_real_index is the raw hash where the record at
    // current_index would naturally land in the hash table if there were no
    // collisions. This test is asking if the record at current_index is
    // invalidly positioned with respect to the required properties of a cluster
    // now that free_slot is vacant.
    bool swap_candidate = current_index > free_slot && (entry_real_index <= free_slot || entry_real_index > current_index);
    bool wrapped_swap_candidate = current_index < free_slot && (entry_real_index <= free_slot && entry_real_index > current_index);
    printf("swap_candidate || wrapped_swap_candidate\n");
    if (swap_candidate || wrapped_swap_candidate)
    {
      table->entries[free_slot].key = table->entries[current_index].key;
      table->entries[current_index].key = NULL;
      table->entries[free_slot].value = table->entries[current_index].value;
      table->entries[current_index].value = NULL;
      free_slot = current_index;
    }
    printf("swapped\n");
    current_index = (current_index + 1) % table->capacity;
  };
}

bool ht_delete(ht *table, const char *key)
{
  size_t index = ht_index(table->capacity, key);
  printf("Deleting %s\n", key);
  if (table->entries[index].key == NULL)
  {
    return false;
  }

  // Loop till we find it
  while (table->entries[index].key != NULL)
  {
    if (strcmp(key, table->entries[index].key) == 0)
    {
      // Found key, delete it and return true.
      free((void *)table->entries[index].key);
      table->entries[index].key = NULL;
      free((void *)table->entries[index].value);
      table->entries[index].value = NULL;
      ht_fill_gap(table, index);
      printf("filled\n");
      table->length--;
      return true;
    }
    // Key wasn't in this slot, move to next (linear probing).
    index++;
    if (index >= table->capacity)
    {
      // At end of entries array, wrap around.
      index = 0;
    }
  }
  return false;
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
  const char *value; // current value

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
  // char word[101];
  // while (scanf("%100s", word) != EOF)
  // {
  //   // Look up word.
  //   void *value = ht_get(counts, word);
  //   if (value != NULL)
  //   {
  //     // Already exists, increment int that value points to.
  //     int *pcount = (int *)value;
  //     (*pcount)++;
  //     continue;
  //   }

  //   // Word not found, allocate space for new int and set to 1.
  //   int *pcount = malloc(sizeof(int));
  //   if (pcount == NULL)
  //   {
  //     exit_nomem();
  //   }
  //   *pcount = 1;
  //   if (ht_set(counts, word, pcount) == NULL)
  //   {
  //     exit_nomem();
  //   }
  // }

  char *key1;
  key1 = (char *)malloc(10 * sizeof(char));
  printf("key: %p\n", key1);
  strcpy(key1, "9\0");

  char *value1;
  value1 = (char *)malloc(10 * sizeof(char));
  printf("value: %p\n", value1);
  strcpy(value1, "987654321\0");

  char *key2;
  key2 = (char *)malloc(10 * sizeof(char));
  printf("key: %p\n", key2);
  strcpy(key2, "10\0");

  char *value2;
  value2 = (char *)malloc(10 * sizeof(char));
  printf("value: %p\n", value2);
  strcpy(value2, "bar\0");

  char *key3;
  key3 = (char *)malloc(10 * sizeof(char));
  printf("key: %p\n", key3);
  strcpy(key3, "29\0");

  char *value3;
  value3 = (char *)malloc(10 * sizeof(char));
  printf("value: %p\n", value3);
  strcpy(value3, "Hello!\0");

  char *key4;
  key4 = (char *)malloc(10 * sizeof(char));
  printf("key: %p\n", key4);
  strcpy(key4, "And this?\0");

  char *value4;
  value4 = (char *)malloc(10 * sizeof(char));
  printf("value: %p\n", value4);
  strcpy(value4, "Hello!\0");

  ht_set(counts, key1, value1);
  ht_set(counts, key2, value2);
  ht_set(counts, key3, value3);
  ht_set(counts, key4, value4);

  bool deletion = ht_delete(counts, key2);
  printf("deletion: %d\n", deletion);
  printf("==========\n");

  // Print out words and frequencies, freeing values as we go.
  printf("iter\n");
  hti it = ht_iterator(counts);
  while (ht_next(&it))
  {
    printf("%s: %s\n", it.key, it.value);
  }

  printf("==========\n");

  for (int i = 0; i < 30; i++)
  {
    char s[10];
    sprintf(s, "%d", i);
    size_t index = ht_index(counts->capacity, s);
    printf("i: %d, s: '%s', index: %zu\n", i, s, index);
  }

  printf("==========\n");

  for (int i = 0; i < counts->capacity; i++)
  {
    printf("i: %02d, key: '%p', *key: %s, value: '%p', *value: %s\n", i, counts->entries[i].key, counts->entries[i].key, counts->entries[i].value, counts->entries[i].value);
  }

  printf("==========\n");

  // Show the number of unique words.
  printf("length: %d\n", (int)ht_length(counts));

  printf("==========\n");
  ht_destroy(counts);

  // return 0;

  socklen_t client_address_length;
  int server_socket_file_descriptor, client_socket_file_descriptor;
  struct sockaddr_in server_address, client_address;

  // socket create and verification
  server_socket_file_descriptor = socket(AF_INET, SOCK_STREAM, 0);
  if (setsockopt(server_socket_file_descriptor, SOL_SOCKET, SO_REUSEADDR, &(int){1}, sizeof(int)) < 0)
  {
    perror("setsockopt(SO_REUSEADDR) failed");
    exit(1);
  }
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
    printf("Server listening: %d..\n", server_socket_file_descriptor);
  }

  client_address_length = sizeof(client_address);
  fd_set rfds;
  struct timeval tv;
  int max_fd = server_socket_file_descriptor;

  ht *clients = ht_create();
  ht *db = ht_create();

  while (1)
  {
    FD_ZERO(&rfds);
    FD_SET(server_socket_file_descriptor, &rfds);

    for (int i = 0; i < clients->capacity; i++)
    {
      printf("i: %02d, key: '%p', *key: %s, value: '%p', *value: %s\n", i, clients->entries[i].key, clients->entries[i].key, clients->entries[i].value, clients->entries[i].value);
    }

    for (int i = 0; i < db->capacity; i++)
    {
      printf("i: %02d, key: '%p', *key: %s, value: '%p', *value: %s\n", i, db->entries[i].key, db->entries[i].key, db->entries[i].value, db->entries[i].value);
    }

    hti it = ht_iterator(clients);
    while (ht_next(&it))
    {
      printf("%s: '%s'\n", it.key, it.value);
      int fd;
      sscanf(it.key, "%d", &fd);
      FD_SET(fd, &rfds);
      if (fd > max_fd)
      {
        max_fd = fd;
      }
    }

    tv.tv_sec = 15;
    tv.tv_usec = 0;
    printf("selecting...\n");
    int ns = select(max_fd + 1, &rfds, NULL, NULL, &tv);
    printf("selected: %d\n", ns);
    if (ns > 0)
    {
      if (FD_ISSET(server_socket_file_descriptor, &rfds))
      {
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
        char *fd_key;
        fd_key = (char *)malloc(10 * sizeof(char));
        sprintf(fd_key, "%d", client_socket_file_descriptor);
        ht_set(clients, fd_key, "");
        FD_CLR(server_socket_file_descriptor, &rfds);

        // char message_buffer[MAX];
        // read(client_socket_file_descriptor, message_buffer, sizeof(message_buffer));
        // printf("From Client: %s\n", message_buffer);
        // bzero(message_buffer, MAX);

        // strcpy(message_buffer, "Hello, this is Server!");
        // write(client_socket_file_descriptor, message_buffer, sizeof(message_buffer));
      }
      else
      {
        hti it2 = ht_iterator(clients);
        while (ht_next(&it2))
        {
          printf("%s: %s\n", it2.key, it2.value);
          int fd;
          sscanf(it2.key, "%d", &fd);
          if (FD_ISSET(fd, &rfds))
          {
            printf("Handling message from %d\n", fd);
            FD_CLR(fd, &rfds);

            char message_buffer[MAX];
            ssize_t res = read(fd, message_buffer, sizeof(message_buffer));
            printf("res: %zd", res);
            if (res == -1)
            {
              // char *fd_key;
              // fd_key = (char *)malloc(10 * sizeof(char));
              // sprintf(fd_key, "%d", client_socket_file_descriptor);
              // ht_delete(clients, fd_key);
              // free(fd_key);
              close(fd);
              continue;
            }
            message_buffer[strcspn(message_buffer, "\n")] = 0;
            printf("From Client: '%s'\n", message_buffer);

            const char *result;
            result = ht_get(db, "123");
            if (result != NULL)
            {
              char response[MAX];
              strcpy(response, result);
              strcat(response, "\n");

              send(fd, response, strlen(response), 0);
            }

            if (ht_get(db, "123") == NULL)
            {
              printf("Initializing 123\n");
              char *key;
              key = (char *)malloc(10 * sizeof(char));
              printf("key: %p\n", key);
              strcpy(key, "123\0");

              char *value;
              value = (char *)malloc(10 * sizeof(char));
              printf("value: %p\n", value);
              strcpy(value, "Hello!\0");
              ht_set(db, key, value);
            }
          }
        }
      }
    }
    else if (ns < 0 && errno == EINTR)
    {
      break;
    }
    else if (ns < 0)
    {
      perror("select");
      exit(EXIT_FAILURE);
    };
  }

  // After chatting close the socket
  printf("Closing server_socket_file_descriptor\n");
  close(server_socket_file_descriptor);
}