#include "safe_ops.h"

#include <stdint.h>
#include <stdio.h>

static uint32_t state = 0xC0FFEEu;

static uint32_t next_value(void) {
    state = state * 1664525u + 1013904223u;
    return state;
}

static size_t reference_count(const uint8_t *data, size_t length, uint8_t needle) {
    size_t count = 0;
    for (size_t i = 0; i < length; ++i) {
        if (data[i] == needle) {
            ++count;
        }
    }
    return count;
}

int main(void) {
    uint8_t data[64];
    for (size_t round = 0; round < 10000; ++round) {
        size_t length = next_value() % (sizeof(data) + 1);
        for (size_t i = 0; i < length; ++i) {
            data[i] = (uint8_t)(next_value() & 0x0Fu);
        }
        uint8_t needle = (uint8_t)(next_value() & 0x0Fu);
        size_t expected = reference_count(data, length, needle);
        size_t actual = count_byte(data, length, needle);
        if (actual != expected) {
            fprintf(stderr,
                    "fuzz mismatch round=%zu length=%zu needle=%u expected=%zu actual=%zu\n",
                    round, length, (unsigned)needle, expected, actual);
            return 1;
        }
    }
    puts("10000 deterministic fuzz-smoke cases passed");
    return 0;
}
