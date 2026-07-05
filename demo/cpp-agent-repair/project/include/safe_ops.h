#ifndef SAFE_OPS_H
#define SAFE_OPS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct CacheNode {
    int key;
    int value;
    struct CacheNode *next;
} CacheNode;

int clamp_percent(int value);

bool frame_copy(uint8_t *dst, size_t capacity, const uint8_t *src, size_t length);

bool checked_packet_size(size_t count, size_t element_size, size_t header_size,
                         size_t *result);

bool cache_remove(CacheNode **head, int key, int *removed_value);

size_t count_byte(const uint8_t *data, size_t length, uint8_t needle);

#endif
