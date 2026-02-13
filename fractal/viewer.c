//
// viewer.c — Interactive SDL2 fractal viewer
//
// Renders Mandelbrot and Julia sets in real-time using NEON assembly kernels.
// Progressive rendering: coarse (1/4 res) for instant feedback, then full res.
//

#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

// Assembly kernels
extern void mandelbrot_row_neon(uint32_t *iter_out, uint32_t width,
                                double x_min, double x_step, double y,
                                uint32_t max_iter);
extern void julia_row_neon(uint32_t *iter_out, uint32_t width,
                           double x_min, double x_step, double y,
                           double jr, double ji, uint32_t max_iter);
extern void colormap_apply(uint8_t *rgb_out, const uint32_t *iter_in,
                           uint32_t count, uint32_t max_iter);

// ── State ────────────────────────────────────────────────

typedef struct {
    uint32_t win_w, win_h;

    double center_x, center_y;
    double zoom;
    uint32_t max_iter;

    int julia_mode;
    double jr, ji;

    int needs_render;
    int progressive_phase;  // 0 = coarse, 1 = full
    double last_render_ms;

    int dragging;
    int drag_start_x, drag_start_y;
    double drag_start_cx, drag_start_cy;
} ViewerState;

// ── Helpers ──────────────────────────────────────────────

static void compute_view(const ViewerState *s,
                         double *x_min, double *y_min,
                         double *x_step, double *y_step,
                         uint32_t rw, uint32_t rh) {
    double aspect = (double)rw / rh;
    double half_h = 2.0 / s->zoom;
    double half_w = half_h * aspect;
    *x_min  = s->center_x - half_w;
    *y_min  = s->center_y - half_h;
    *x_step = (2.0 * half_w) / rw;
    *y_step = (2.0 * half_h) / rh;
}

static double render_fractal(const ViewerState *s,
                             uint32_t *iter_buf, uint8_t *rgb_buf,
                             uint32_t rw, uint32_t rh) {
    double x_min, y_min, x_step, y_step;
    compute_view(s, &x_min, &y_min, &x_step, &y_step, rw, rh);

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    for (uint32_t row = 0; row < rh; row++) {
        double y = y_min + row * y_step;
        uint32_t *row_buf = iter_buf + (size_t)row * rw;
        if (s->julia_mode)
            julia_row_neon(row_buf, rw, x_min, x_step, y,
                           s->jr, s->ji, s->max_iter);
        else
            mandelbrot_row_neon(row_buf, rw, x_min, x_step, y,
                                s->max_iter);
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);

    colormap_apply(rgb_buf, iter_buf, rw * rh, s->max_iter);

    return (t1.tv_sec - t0.tv_sec) * 1000.0
         + (t1.tv_nsec - t0.tv_nsec) / 1e6;
}

static void rgb24_to_argb32(void *dst, int pitch,
                            const uint8_t *rgb,
                            uint32_t w, uint32_t h) {
    for (uint32_t y = 0; y < h; y++) {
        uint32_t *drow = (uint32_t *)((uint8_t *)dst + y * pitch);
        const uint8_t *srow = rgb + y * w * 3;
        for (uint32_t x = 0; x < w; x++) {
            uint8_t r = srow[x * 3];
            uint8_t g = srow[x * 3 + 1];
            uint8_t b = srow[x * 3 + 2];
            drow[x] = 0xFF000000u | ((uint32_t)r << 16)
                     | ((uint32_t)g << 8) | b;
        }
    }
}

static void update_title(SDL_Window *win, const ViewerState *s) {
    char title[256];
    if (s->julia_mode)
        snprintf(title, sizeof(title),
            "Julia c=(%.4f, %.4f) | (%.6f, %.6f) z=%.1f i=%u | %.1fms",
            s->jr, s->ji, s->center_x, s->center_y,
            s->zoom, s->max_iter, s->last_render_ms);
    else
        snprintf(title, sizeof(title),
            "Mandelbrot | (%.6f, %.6f) z=%.1f i=%u | %.1fms",
            s->center_x, s->center_y, s->zoom,
            s->max_iter, s->last_render_ms);
    SDL_SetWindowTitle(win, title);
}

static void save_ppm(const ViewerState *s, const uint8_t *rgb,
                     uint32_t w, uint32_t h) {
    char filename[128];
    snprintf(filename, sizeof(filename), "fractal_%ld.ppm", (long)time(NULL));
    FILE *f = fopen(filename, "wb");
    if (!f) { fprintf(stderr, "Cannot write %s\n", filename); return; }
    fprintf(f, "P6\n%u %u\n255\n", w, h);
    fwrite(rgb, 3, (size_t)w * h, f);
    fclose(f);
    fprintf(stderr, "Saved %s (%ux%u)\n", filename, w, h);
}

// ── Screen coordinate → complex plane ───────────────────

static void screen_to_complex(const ViewerState *s, int sx, int sy,
                              double *re, double *im) {
    double aspect = (double)s->win_w / s->win_h;
    double half_h = 2.0 / s->zoom;
    double half_w = half_h * aspect;
    *re = s->center_x - half_w + (2.0 * half_w) * sx / s->win_w;
    *im = s->center_y - half_h + (2.0 * half_h) * sy / s->win_h;
}

// ── Event handlers ───────────────────────────────────────

static void mark_dirty(ViewerState *s) {
    s->needs_render = 1;
    s->progressive_phase = 0;
}

static void handle_key(ViewerState *s, SDL_Keycode key,
                       int *running, const uint8_t *rgb,
                       uint32_t rw, uint32_t rh) {
    switch (key) {
    case SDLK_ESCAPE:
    case SDLK_q:
        *running = 0;
        break;

    case SDLK_SPACE:
        s->julia_mode = 0;
        s->center_x = -0.5;
        s->center_y = 0.0;
        s->zoom = 1.0;
        mark_dirty(s);
        break;

    case SDLK_EQUALS:
    case SDLK_PLUS:
    case SDLK_KP_PLUS:
        s->max_iter = s->max_iter * 2;
        if (s->max_iter > 65536) s->max_iter = 65536;
        mark_dirty(s);
        break;

    case SDLK_MINUS:
    case SDLK_KP_MINUS:
        s->max_iter = s->max_iter / 2;
        if (s->max_iter < 16) s->max_iter = 16;
        mark_dirty(s);
        break;

    case SDLK_r:
        s->center_x = s->julia_mode ? 0.0 : -0.5;
        s->center_y = 0.0;
        s->zoom = 1.0;
        s->max_iter = 256;
        mark_dirty(s);
        break;

    case SDLK_s:
        save_ppm(s, rgb, rw, rh);
        break;
    }
}

static void handle_mousedown(ViewerState *s, SDL_MouseButtonEvent *ev) {
    if (ev->button == SDL_BUTTON_LEFT) {
        s->dragging = 1;
        s->drag_start_x = ev->x;
        s->drag_start_y = ev->y;
        s->drag_start_cx = s->center_x;
        s->drag_start_cy = s->center_y;
    } else if (ev->button == SDL_BUTTON_RIGHT && !s->julia_mode) {
        double re, im;
        screen_to_complex(s, ev->x, ev->y, &re, &im);
        s->jr = re;
        s->ji = im;
        s->julia_mode = 1;
        s->center_x = 0.0;
        s->center_y = 0.0;
        s->zoom = 1.0;
        mark_dirty(s);
        fprintf(stderr, "Julia mode: c = (%.6f, %.6f)\n", re, im);
    }
}

static void handle_mouseup(ViewerState *s, SDL_MouseButtonEvent *ev) {
    if (ev->button == SDL_BUTTON_LEFT)
        s->dragging = 0;
}

static void handle_mousemotion(ViewerState *s, SDL_MouseMotionEvent *ev) {
    if (!s->dragging) return;

    double aspect = (double)s->win_w / s->win_h;
    double half_h = 2.0 / s->zoom;
    double half_w = half_h * aspect;

    double dx = (double)(ev->x - s->drag_start_x) / s->win_w * 2.0 * half_w;
    double dy = (double)(ev->y - s->drag_start_y) / s->win_h * 2.0 * half_h;

    s->center_x = s->drag_start_cx - dx;
    s->center_y = s->drag_start_cy - dy;
    mark_dirty(s);
}

static void handle_wheel(ViewerState *s, SDL_MouseWheelEvent *ev) {
    int mx, my;
    SDL_GetMouseState(&mx, &my);

    // Point under cursor before zoom
    double cx, cy;
    screen_to_complex(s, mx, my, &cx, &cy);

    // Zoom
    double factor = (ev->y > 0) ? 1.3 : (1.0 / 1.3);
    s->zoom *= factor;
    if (s->zoom < 0.1) s->zoom = 0.1;
    if (s->zoom > 1e14) s->zoom = 1e14;

    // Adjust center so (cx, cy) stays under cursor
    double aspect = (double)s->win_w / s->win_h;
    double new_half_h = 2.0 / s->zoom;
    double new_half_w = new_half_h * aspect;
    double fx = (double)mx / s->win_w;
    double fy = (double)my / s->win_h;
    s->center_x = cx - new_half_w * (2.0 * fx - 1.0);
    s->center_y = cy - new_half_h * (2.0 * fy - 1.0);

    mark_dirty(s);
}

// ── CLI ──────────────────────────────────────────────────

static void parse_args(int argc, char **argv, ViewerState *s) {
    int center_x_set = 0;
    int opt;
    while ((opt = getopt(argc, argv, "w:h:j:i:x:y:z:")) != -1) {
        switch (opt) {
        case 'w': s->win_w = (uint32_t)atoi(optarg); break;
        case 'h': s->win_h = (uint32_t)atoi(optarg); break;
        case 'j':
            s->julia_mode = 1;
            if (sscanf(optarg, "%lf,%lf", &s->jr, &s->ji) != 2) {
                fprintf(stderr, "Bad -j format. Use: -j JR,JI\n");
                exit(1);
            }
            break;
        case 'i': s->max_iter = (uint32_t)atoi(optarg); break;
        case 'x': s->center_x = atof(optarg); center_x_set = 1; break;
        case 'y': s->center_y = atof(optarg); break;
        case 'z': s->zoom = atof(optarg); break;
        default:
            fprintf(stderr,
                "Usage: %s [-w width] [-h height] [-j jr,ji] "
                "[-i maxiter] [-x cx] [-y cy] [-z zoom]\n", argv[0]);
            exit(1);
        }
    }
    if (s->julia_mode && !center_x_set)
        s->center_x = 0.0;
}

// ── Main ─────────────────────────────────────────────────

int main(int argc, char **argv) {
    ViewerState state = {
        .win_w = 800, .win_h = 600,
        .center_x = -0.5, .center_y = 0.0,
        .zoom = 1.0, .max_iter = 256,
        .julia_mode = 0, .jr = 0, .ji = 0,
        .needs_render = 1, .progressive_phase = 0,
        .last_render_ms = 0, .dragging = 0
    };
    parse_args(argc, argv, &state);

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window *win = SDL_CreateWindow(
        "Fractal Viewer",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        state.win_w, state.win_h, SDL_WINDOW_SHOWN);
    if (!win) { fprintf(stderr, "Window: %s\n", SDL_GetError()); return 1; }

    SDL_Renderer *renderer = SDL_CreateRenderer(
        win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer) {
        fprintf(stderr, "Renderer: %s\n", SDL_GetError());
        return 1;
    }

    // Coarse texture (1/4 res) — nearest-neighbor scaling for blocky preview
    uint32_t cw = state.win_w / 4, ch = state.win_h / 4;
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
    SDL_Texture *tex_coarse = SDL_CreateTexture(
        renderer, SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING, cw, ch);

    // Full texture — linear scaling
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1");
    SDL_Texture *tex_full = SDL_CreateTexture(
        renderer, SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING, state.win_w, state.win_h);

    SDL_Texture *active_tex = tex_full;

    // Buffers
    size_t full_px = (size_t)state.win_w * state.win_h;
    size_t coarse_px = (size_t)cw * ch;

    uint32_t *iter_buf   = malloc(full_px * sizeof(uint32_t));
    uint8_t  *rgb_buf    = malloc(full_px * 3);
    uint32_t *iter_small = malloc(coarse_px * sizeof(uint32_t));
    uint8_t  *rgb_small  = malloc(coarse_px * 3);

    fprintf(stderr,
        "Controls: drag=pan  scroll=zoom  right-click=Julia  "
        "space=Mandelbrot  +/-=iters  S=save  R=reset  Q=quit\n");

    int running = 1;
    while (running) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            switch (ev.type) {
            case SDL_QUIT:
                running = 0;
                break;
            case SDL_KEYDOWN:
                handle_key(&state, ev.key.keysym.sym, &running,
                           rgb_buf, state.win_w, state.win_h);
                break;
            case SDL_MOUSEBUTTONDOWN:
                handle_mousedown(&state, &ev.button);
                break;
            case SDL_MOUSEBUTTONUP:
                handle_mouseup(&state, &ev.button);
                break;
            case SDL_MOUSEMOTION:
                handle_mousemotion(&state, &ev.motion);
                break;
            case SDL_MOUSEWHEEL:
                handle_wheel(&state, &ev.wheel);
                break;
            }
        }

        if (state.needs_render) {
            if (state.progressive_phase == 0) {
                // Coarse pass — fast preview
                double ms = render_fractal(&state, iter_small,
                                           rgb_small, cw, ch);
                void *pixels; int pitch;
                SDL_LockTexture(tex_coarse, NULL, &pixels, &pitch);
                rgb24_to_argb32(pixels, pitch, rgb_small, cw, ch);
                SDL_UnlockTexture(tex_coarse);

                active_tex = tex_coarse;
                state.progressive_phase = 1;
                state.last_render_ms = ms;
                update_title(win, &state);
            } else {
                // Full pass
                double ms = render_fractal(&state, iter_buf,
                                           rgb_buf, state.win_w, state.win_h);
                void *pixels; int pitch;
                SDL_LockTexture(tex_full, NULL, &pixels, &pitch);
                rgb24_to_argb32(pixels, pitch, rgb_buf,
                                state.win_w, state.win_h);
                SDL_UnlockTexture(tex_full);

                active_tex = tex_full;
                state.needs_render = 0;
                state.last_render_ms = ms;
                update_title(win, &state);
            }
        }

        SDL_RenderClear(renderer);
        SDL_RenderCopy(renderer, active_tex, NULL, NULL);
        SDL_RenderPresent(renderer);

        if (!state.needs_render)
            SDL_Delay(8);
    }

    free(iter_buf);
    free(rgb_buf);
    free(iter_small);
    free(rgb_small);
    SDL_DestroyTexture(tex_full);
    SDL_DestroyTexture(tex_coarse);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
}
