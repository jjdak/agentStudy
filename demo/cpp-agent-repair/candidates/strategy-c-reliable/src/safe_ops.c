#include "safe_ops.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int clamp_percent(int value) {
    if (value < 0) {
        return 0;
    }
    if (value > 100) {
        return 100;
    }
    return value;
}

bool frame_copy(uint8_t *dst, size_t capacity, const uint8_t *src, size_t length) {
    if (length > capacity || (length > 0 && (dst == NULL || src == NULL))) {
        return false;
    }
    if (length > 0) {
        memcpy(dst, src, length);
    }
    return true;
}

bool checked_packet_size(size_t count, size_t element_size, size_t header_size,
                         size_t *result) {
    if (result == NULL) {
        return false;
    }
    if (count != 0 && element_size > (SIZE_MAX - header_size) / count) {
        return false;
    }
    *result = count * element_size + header_size;
    return true;
}

bool cache_remove(CacheNode **head, int key, int *removed_value) {
    if (head == NULL || removed_value == NULL) {
        return false;
    }
    CacheNode **link = head;
    while (*link != NULL) {
        CacheNode *current = *link;
        if (current->key == key) {
            int value = current->value;
            *link = current->next;
            free(current);
            *removed_value = value;
            return true;
        }
        link = &current->next;
    }
    return false;
}

size_t count_byte(const uint8_t *data, size_t length, uint8_t needle) {
    if (data == NULL && length != 0) {
        return 0;
    }
    size_t count = 0;
    for (size_t i = 0; i < length; ++i) {
        if (data[i] == needle) {
            ++count;
        }
    }
    return count;
}
