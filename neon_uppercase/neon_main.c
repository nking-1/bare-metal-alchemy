#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* Implemented in neon_upper.asm */
extern void neon_toupper(char *str, uint64_t len);
extern void scalar_toupper(char *str, uint64_t len);

static double seconds_between(LARGE_INTEGER start, LARGE_INTEGER end, LARGE_INTEGER freq)
{
    return (double)(end.QuadPart - start.QuadPart) / (double)freq.QuadPart;
}

int main(void)
{
    /* ── Part 1: Visual demo ── */
    const char *demo = "Hello, World! NEON on arm64 Windows is WILD.";
    size_t len = strlen(demo);

    char *buf_scalar = _strdup(demo);
    char *buf_neon   = _strdup(demo);

    printf("=== NEON SIMD uppercase demo ===\n\n");
    printf("  Original:  \"%s\"\n", demo);

    scalar_toupper(buf_scalar, len);
    printf("  Scalar:    \"%s\"\n", buf_scalar);

    neon_toupper(buf_neon, len);
    printf("  NEON:      \"%s\"\n\n", buf_neon);

    /* Verify they match */
    if (memcmp(buf_scalar, buf_neon, len) == 0)
        printf("  [OK] Both produce identical output.\n");
    else
        printf("  [BUG] Outputs differ!\n");

    free(buf_scalar);
    free(buf_neon);

    /* ── Part 2: Speed comparison ── */
    printf("\n=== Speed test: 1 MB buffer x 1000 iterations ===\n\n");

    size_t big_len = 1024 * 1024;
    int iterations = 1000;

    char *big_scalar = (char *)malloc(big_len);
    char *big_neon   = (char *)malloc(big_len);

    LARGE_INTEGER freq, t0, t1;
    QueryPerformanceFrequency(&freq);

    /* Fill with repeating lowercase text */
    for (size_t i = 0; i < big_len; i++)
        big_scalar[i] = 'a' + (char)(i % 26);

    /* --- Scalar timing --- */
    QueryPerformanceCounter(&t0);
    for (int n = 0; n < iterations; n++) {
        memcpy(big_scalar, big_neon, big_len);  /* reset to lowercase */
        /* Oops, need to fill big_neon first. Let me fix the order. */
    }
    /* Actually, let's just refill each time from a pattern. */
    /* Simpler: time the conversion only, refill from a source buffer. */

    char *source = (char *)malloc(big_len);
    for (size_t i = 0; i < big_len; i++)
        source[i] = 'a' + (char)(i % 26);

    /* Time scalar */
    QueryPerformanceCounter(&t0);
    for (int n = 0; n < iterations; n++) {
        memcpy(big_scalar, source, big_len);
        scalar_toupper(big_scalar, big_len);
    }
    QueryPerformanceCounter(&t1);
    double scalar_time = seconds_between(t0, t1, freq);

    /* Time NEON */
    QueryPerformanceCounter(&t0);
    for (int n = 0; n < iterations; n++) {
        memcpy(big_neon, source, big_len);
        neon_toupper(big_neon, big_len);
    }
    QueryPerformanceCounter(&t1);
    double neon_time = seconds_between(t0, t1, freq);

    /* Verify results match */
    int match = (memcmp(big_scalar, big_neon, big_len) == 0);

    printf("  Scalar: %.3f ms  (%6.1f MB/s)\n",
           scalar_time * 1000.0,
           (big_len * iterations) / scalar_time / (1024.0 * 1024.0));
    printf("  NEON:   %.3f ms  (%6.1f MB/s)\n",
           neon_time * 1000.0,
           (big_len * iterations) / neon_time / (1024.0 * 1024.0));
    printf("  Speedup: %.1fx\n", scalar_time / neon_time);
    printf("  Results match: %s\n", match ? "YES" : "NO (BUG!)");

    free(source);
    free(big_scalar);
    free(big_neon);

    return 0;
}
