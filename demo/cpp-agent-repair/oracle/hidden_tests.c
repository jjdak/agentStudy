#include "safe_ops.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int failures = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            fprintf(stderr, "HIDDEN FAIL %s:%d: %s\n", __FILE__, __LINE__,      \
                    #condition);                                                \
            ++failures;                                                         \
        }                                                                       \
    } while (0)

static void test_logic_boundaries(void) {
    CHECK(clamp_percent(100) == 100);
    CHECK(clamp_percent(101) == 100);
    CHECK(clamp_percent(0) == 0);
}

static void test_frame_boundaries(void) {
    const uint8_t source[] = {1, 2, 3, 4};
    uint8_t exact[5] = {0, 0, 0, 0, 0xA5};
    CHECK(frame_copy(exact, 4, source, 4));
    CHECK(exact[0] == 1 && exact[3] == 4);
    CHECK(exact[4] == 0xA5);

    uint8_t short_buffer[3] = {9, 9, 9};
    CHECK(!frame_copy(short_buffer, 3, source, 4));
    CHECK(short_buffer[0] == 9 && short_buffer[2] == 9);
    CHECK(frame_copy(NULL, 0, NULL, 0));
}

static void test_integer_overflow(void) {
    size_t result = 123;
    CHECK(!checked_packet_size(SIZE_MAX, 2, 0, &result));
    CHECK(!checked_packet_size(1, SIZE_MAX, 1, &result));
    CHECK(checked_packet_size(0, SIZE_MAX, 7, &result));
    CHECK(result == 7);
}

static void test_cache_lifetime(void) {
    CacheNode *first = malloc(sizeof(*first));
    CacheNode *second = malloc(sizeof(*second));
    CHECK(first != NULL && second != NULL);
    if (first == NULL || second == NULL) {
        free(first);
        free(second);
        return;
    }
    first->key = 1;
    first->value = 11;
    first->next = second;
    second->key = 2;
    second->value = 22;
    second->next = NULL;

    int removed = 0;
    CHECK(cache_remove(&first, 1, &removed));
    CHECK(removed == 11);
    CHECK(first == second);
    CHECK(first->key == 2 && first->value == 22);
    CHECK(!cache_remove(&first, 99, &removed));
    CHECK(cache_remove(&first, 2, &removed));
    CHECK(removed == 22 && first == NULL);
}

static void test_binary_regression(void) {
    const uint8_t binary[] = {'A', 0, 'A', 0, 'B', 'A'};
    CHECK(count_byte(binary, sizeof(binary), (uint8_t)'A') == 3);
    CHECK(count_byte(binary, sizeof(binary), 0) == 2);
    CHECK(count_byte(NULL, 0, 7) == 0);
}

int main(void) {
    test_logic_boundaries();
    test_frame_boundaries();
    test_integer_overflow();
    test_cache_lifetime();
    test_binary_regression();
    if (failures != 0) {
        fprintf(stderr, "%d hidden checks failed\n", failures);
        return 1;
    }
    puts("all hidden checks passed");
    return 0;
}
