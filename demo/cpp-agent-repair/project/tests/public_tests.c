#include "safe_ops.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int failures = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition); \
            ++failures;                                                         \
        }                                                                       \
    } while (0)

static void test_reported_logic_bug(void) {
    CHECK(clamp_percent(-3) == 0);
    CHECK(clamp_percent(120) == 100);
    CHECK(clamp_percent(40) == 40);
}

static void test_normal_frame(void) {
    const uint8_t source[] = {'A', 'B', 'C', 0};
    uint8_t destination[8] = {0};
    CHECK(frame_copy(destination, sizeof(destination), source, 3));
    CHECK(destination[0] == 'A' && destination[2] == 'C');
}

static void test_normal_size(void) {
    size_t result = 0;
    CHECK(checked_packet_size(4, 8, 16, &result));
    CHECK(result == 48);
}

static void test_cache_remove(void) {
    CacheNode *node = malloc(sizeof(*node));
    CHECK(node != NULL);
    if (node == NULL) {
        return;
    }
    node->key = 7;
    node->value = 42;
    node->next = NULL;
    int removed = 0;
    CHECK(!cache_remove(&node, 99, &removed));
    CHECK(node != NULL);
    free(node);
}

static void test_text_count(void) {
    const uint8_t text[] = "banana";
    CHECK(count_byte(text, 6, (uint8_t)'a') == 3);
}

int main(void) {
    test_reported_logic_bug();
    test_normal_frame();
    test_normal_size();
    test_cache_remove();
    test_text_count();
    if (failures != 0) {
        fprintf(stderr, "%d public checks failed\n", failures);
        return 1;
    }
    puts("all public checks passed");
    return 0;
}
