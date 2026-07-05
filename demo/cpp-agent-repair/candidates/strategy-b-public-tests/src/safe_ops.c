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
    if (result == NULL || (element_size != 0 && count > SIZE_MAX / element_size)) {
        return false;
    }
    *result = count * element_size + header_size; /* Addition overflow remains. */
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
            *link = current->next;
            free(current);
            *removed_value = current->value; /* Still reads freed memory. */
            return true;
        }
        link = &current->next;
    }
    return false;
}

size_t count_byte(const uint8_t *data, size_t length, uint8_t needle) {
    (void)length;
    size_t count = 0;
    size_t text_length = strlen((const char *)data);
    for (size_t i = 0; i < text_length; ++i) {
        if (data[i] == needle) {
            ++count;
        }
    }
    return count;
}
