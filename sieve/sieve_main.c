#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

/* Implemented in sieve.asm */
extern void sieve(uint8_t *buffer, uint32_t limit);

int main(int argc, char *argv[])
{
    uint32_t limit = 100;
    if (argc > 1)
        limit = (uint32_t)atoi(argv[1]);

    uint8_t *buf = (uint8_t *)calloc(limit + 1, 1);
    if (!buf) {
        fprintf(stderr, "out of memory\n");
        return 1;
    }

    sieve(buf, limit);

    printf("Primes up to %u:\n", limit);
    int count = 0;
    for (uint32_t i = 2; i <= limit; i++) {
        if (buf[i]) {
            printf("%u ", i);
            count++;
        }
    }
    printf("\n\nFound %d primes.\n", count);

    free(buf);
    return 0;
}
