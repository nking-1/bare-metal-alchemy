//
// fractal_main.c — CLI driver for Mandelbrot/Julia renderer
//
// All compute is done in AArch64 assembly kernels.
// This file handles CLI args, memory, PPM output, and benchmarking.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>

// Assembly kernels
extern void mandelbrot_row_scalar(uint32_t *iter_out, uint32_t width,
                                  double x_min, double x_step, double y,
                                  uint32_t max_iter);
extern void mandelbrot_row_neon(uint32_t *iter_out, uint32_t width,
                                double x_min, double x_step, double y,
                                uint32_t max_iter);
extern void julia_row_scalar(uint32_t *iter_out, uint32_t width,
                             double x_min, double x_step, double y,
                             double jr, double ji, uint32_t max_iter);
extern void julia_row_neon(uint32_t *iter_out, uint32_t width,
                           double x_min, double x_step, double y,
                           double jr, double ji, uint32_t max_iter);
extern void colormap_apply(uint8_t *rgb_out, const uint32_t *iter_in,
                           uint32_t count, uint32_t max_iter);

typedef struct {
    uint32_t width, height;
    double center_x, center_y;
    double zoom;
    uint32_t max_iter;
    int julia_mode;
    double jr, ji;
    const char *output;
    int benchmark;
} Config;

static double timespec_diff_ms(struct timespec *a, struct timespec *b) {
    return (b->tv_sec - a->tv_sec) * 1000.0
         + (b->tv_nsec - a->tv_nsec) / 1e6;
}

static void write_ppm(const char *path, const uint8_t *rgb,
                      uint32_t w, uint32_t h) {
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); exit(1); }
    fprintf(f, "P6\n%u %u\n255\n", w, h);
    fwrite(rgb, 3, (size_t)w * h, f);
    fclose(f);
}

static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s [options]\n"
        "  -w WIDTH      image width   (default 1920)\n"
        "  -h HEIGHT     image height  (default 1080)\n"
        "  -x CENTER_X   real center   (default -0.5 / 0.0 for julia)\n"
        "  -y CENTER_Y   imag center   (default 0.0)\n"
        "  -z ZOOM       zoom level    (default 1.0)\n"
        "  -i MAX_ITER   max iterations (default 256)\n"
        "  -j JR,JI      julia mode    (e.g. -j -0.7,0.27015)\n"
        "  -o FILE       output file   (default fractal.ppm)\n"
        "  -b            benchmark scalar vs NEON\n",
        prog);
    exit(1);
}

static void render_rows(uint32_t *iters, const Config *cfg,
                        double x_min, double x_step,
                        double y_min, double y_step,
                        int use_neon) {
    for (uint32_t row = 0; row < cfg->height; row++) {
        double y = y_min + row * y_step;
        uint32_t *row_buf = iters + (size_t)row * cfg->width;

        if (cfg->julia_mode) {
            if (use_neon)
                julia_row_neon(row_buf, cfg->width, x_min, x_step, y,
                               cfg->jr, cfg->ji, cfg->max_iter);
            else
                julia_row_scalar(row_buf, cfg->width, x_min, x_step, y,
                                 cfg->jr, cfg->ji, cfg->max_iter);
        } else {
            if (use_neon)
                mandelbrot_row_neon(row_buf, cfg->width, x_min, x_step, y,
                                   cfg->max_iter);
            else
                mandelbrot_row_scalar(row_buf, cfg->width, x_min, x_step, y,
                                     cfg->max_iter);
        }
    }
}

int main(int argc, char **argv) {
    Config cfg = {
        .width = 1920,
        .height = 1080,
        .center_x = -0.5,
        .center_y = 0.0,
        .zoom = 1.0,
        .max_iter = 256,
        .julia_mode = 0,
        .jr = 0, .ji = 0,
        .output = "fractal.ppm",
        .benchmark = 0
    };

    int center_x_set = 0;
    int opt;
    while ((opt = getopt(argc, argv, "w:h:x:y:z:i:j:o:b")) != -1) {
        switch (opt) {
        case 'w': cfg.width    = (uint32_t)atoi(optarg); break;
        case 'h': cfg.height   = (uint32_t)atoi(optarg); break;
        case 'x': cfg.center_x = atof(optarg); center_x_set = 1; break;
        case 'y': cfg.center_y = atof(optarg); break;
        case 'z': cfg.zoom     = atof(optarg); break;
        case 'i': cfg.max_iter = (uint32_t)atoi(optarg); break;
        case 'j':
            cfg.julia_mode = 1;
            if (sscanf(optarg, "%lf,%lf", &cfg.jr, &cfg.ji) != 2) {
                fprintf(stderr, "Bad -j format. Use: -j JR,JI\n");
                exit(1);
            }
            break;
        case 'o': cfg.output = optarg; break;
        case 'b': cfg.benchmark = 1; break;
        default:  usage(argv[0]);
        }
    }

    // Default center for Julia mode
    if (cfg.julia_mode && !center_x_set)
        cfg.center_x = 0.0;

    // Compute view bounds
    double aspect = (double)cfg.width / cfg.height;
    double half_h = 2.0 / cfg.zoom;
    double half_w = half_h * aspect;
    double x_min  = cfg.center_x - half_w;
    double y_min  = cfg.center_y - half_h;
    double x_step = (2.0 * half_w) / cfg.width;
    double y_step = (2.0 * half_h) / cfg.height;

    size_t npixels = (size_t)cfg.width * cfg.height;
    uint32_t *iters = malloc(npixels * sizeof(uint32_t));
    uint8_t  *rgb   = malloc(npixels * 3);
    if (!iters || !rgb) { perror("malloc"); exit(1); }

    if (cfg.benchmark) {
        struct timespec t0, t1, t2;

        // Scalar pass
        clock_gettime(CLOCK_MONOTONIC, &t0);
        render_rows(iters, &cfg, x_min, x_step, y_min, y_step, 0);
        clock_gettime(CLOCK_MONOTONIC, &t1);

        // NEON pass
        render_rows(iters, &cfg, x_min, x_step, y_min, y_step, 1);
        clock_gettime(CLOCK_MONOTONIC, &t2);

        double scalar_ms = timespec_diff_ms(&t0, &t1);
        double neon_ms   = timespec_diff_ms(&t1, &t2);

        printf("%-10s %ux%u, max_iter=%u, zoom=%.1f\n",
               cfg.julia_mode ? "Julia" : "Mandelbrot",
               cfg.width, cfg.height, cfg.max_iter, cfg.zoom);
        printf("Scalar:    %.1f ms\n", scalar_ms);
        printf("NEON:      %.1f ms\n", neon_ms);
        printf("Speedup:   %.2fx\n", scalar_ms / neon_ms);
    } else {
        // NEON only (default)
        render_rows(iters, &cfg, x_min, x_step, y_min, y_step, 1);
    }

    colormap_apply(rgb, iters, (uint32_t)npixels, cfg.max_iter);
    write_ppm(cfg.output, rgb, cfg.width, cfg.height);

    printf("Wrote %s (%ux%u)\n", cfg.output, cfg.width, cfg.height);

    free(iters);
    free(rgb);
    return 0;
}
