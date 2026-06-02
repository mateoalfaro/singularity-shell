/* singularity-screenshot - native Wayland screenshot using wlr-screencopy-unstable-v1
 *
 * Usage: singularity-screenshot [-c] [-o output] [-g "x,y WxH"] <file.png>
 *   -c          include cursor
 *   -o <name>   capture named output only
 *   -g "x,y WxH" capture region (grim-compatible format)
 *   (no flags)  capture all outputs composited side-by-side
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <png.h>
#include <wayland-client.h>
#include "wlr-screencopy-unstable-v1-client-protocol.h"
#include "xdg-output-unstable-v1-client-protocol.h"

#define MAX_OUTPUTS 16

/* ── Output tracking ─────────────────────────────────────────────────────── */

typedef struct {
    struct wl_output *wl;
    int32_t  x, y;           /* logical compositor position (from xdg-output or wl_output.geometry) */
    int32_t  mode_w, mode_h; /* pixel dimensions */
    int32_t  logical_w, logical_h; /* logical dimensions from xdg-output */
    int32_t  scale;
    char     name[64];
    int      xdg_done;       /* xdg_output done event received */
} Output;

typedef struct {
    struct wl_display                 *display;
    struct wl_shm                     *shm;
    struct zwlr_screencopy_manager_v1 *screencopy;
    struct zxdg_output_manager_v1     *xdg_output_manager;
    Output   outputs[MAX_OUTPUTS];
    int      n_outputs;
} State;

/* ── Frame capture state ──────────────────────────────────────────────────── */

typedef struct {
    State    *state;
    uint32_t  format, width, height, stride;
    uint32_t  flags;
    int       fd;
    void     *data;
    size_t    size;
    struct wl_buffer *buffer;
    int  shm_received;
    int  bgr_order;  /* 1 if format is XBGR/ABGR (bytes R,G,B,X - no swap needed) */
    int  done;   /* 1=ready, -1=failed, 0=pending */
} Frame;

/* ── SHM buffer ───────────────────────────────────────────────────────────── */

static struct wl_buffer *alloc_shm_buffer(Frame *f) {
    f->size = (size_t)f->stride * f->height;
    f->fd = memfd_create("screenshot", MFD_CLOEXEC);
    if (f->fd < 0) { perror("memfd_create"); return NULL; }
    if (ftruncate(f->fd, (off_t)f->size) < 0) {
        perror("ftruncate"); close(f->fd); f->fd = -1; return NULL;
    }
    f->data = mmap(NULL, f->size, PROT_READ | PROT_WRITE, MAP_SHARED, f->fd, 0);
    if (f->data == MAP_FAILED) {
        perror("mmap"); close(f->fd); f->fd = -1; return NULL;
    }
    struct wl_shm_pool *pool = wl_shm_create_pool(f->state->shm, f->fd, (int32_t)f->size);
    struct wl_buffer *buf = wl_shm_pool_create_buffer(pool, 0,
        (int32_t)f->width, (int32_t)f->height, (int32_t)f->stride, f->format);
    wl_shm_pool_destroy(pool);
    return buf;
}

static void frame_cleanup(Frame *f) {
    if (f->buffer)  { wl_buffer_destroy(f->buffer); f->buffer = NULL; }
    if (f->data && f->data != MAP_FAILED) { munmap(f->data, f->size); f->data = NULL; }
    if (f->fd >= 0) { close(f->fd); f->fd = -1; }
}

/* ── Frame event listeners ────────────────────────────────────────────────── */

static void frame_ev_buffer(void *data, struct zwlr_screencopy_frame_v1 *obj,
    uint32_t format, uint32_t w, uint32_t h, uint32_t stride)
{
    (void)obj;
    Frame *f = data;
    /* Accept common 32bpp wl_shm and DRM fourcc formats.
     * XR24=0x34325258 (XRGB, bytes B,G,R,X), XB24=0x34324258 (XBGR, bytes R,G,B,X),
     * and their ARGB/ABGR variants. */
    int is_bgr = (format == 0x34324258 || format == 0x34324241);
    if (format == WL_SHM_FORMAT_ARGB8888 || format == WL_SHM_FORMAT_XRGB8888 ||
        format == 0x34325241 || format == 0x34325258 ||
        format == 0x34324241 || format == 0x34324258) {
        f->format = format;
        f->width = w; f->height = h; f->stride = stride;
        f->shm_received = 1;
        f->bgr_order = is_bgr;
    }
}

static void frame_ev_flags(void *data, struct zwlr_screencopy_frame_v1 *obj, uint32_t flags) {
    (void)obj; ((Frame *)data)->flags = flags;
}

static void frame_ev_ready(void *data, struct zwlr_screencopy_frame_v1 *obj,
    uint32_t hi, uint32_t lo, uint32_t ns)
{
    (void)obj; (void)hi; (void)lo; (void)ns;
    ((Frame *)data)->done = 1;
}

static void frame_ev_failed(void *data, struct zwlr_screencopy_frame_v1 *obj) {
    (void)obj; Frame *f = data; f->done = -1;
}

static void frame_ev_damage(void *data, struct zwlr_screencopy_frame_v1 *obj,
    uint32_t x, uint32_t y, uint32_t w, uint32_t h)
{
    (void)data; (void)obj; (void)x; (void)y; (void)w; (void)h;
}

static void frame_ev_linux_dmabuf(void *data, struct zwlr_screencopy_frame_v1 *obj,
    uint32_t fmt, uint32_t w, uint32_t h)
{
    (void)data; (void)obj; (void)fmt; (void)w; (void)h;
}

/* v3: all buffer-type events have been sent; allocate shm and start the copy */
static void frame_ev_buffer_done(void *data, struct zwlr_screencopy_frame_v1 *obj) {
    Frame *f = data;
    if (!f->shm_received) { f->done = -1; return; }
    f->buffer = alloc_shm_buffer(f);
    if (!f->buffer) { f->done = -1; return; }
    zwlr_screencopy_frame_v1_copy(obj, f->buffer);
}

static const struct zwlr_screencopy_frame_v1_listener frame_listener = {
    .buffer       = frame_ev_buffer,
    .flags        = frame_ev_flags,
    .ready        = frame_ev_ready,
    .failed       = frame_ev_failed,
    .damage       = frame_ev_damage,
    .linux_dmabuf = frame_ev_linux_dmabuf,
    .buffer_done  = frame_ev_buffer_done,
};

/* ── wl_output listeners ──────────────────────────────────────────────────── */

static void output_geometry(void *data, struct wl_output *wl,
    int32_t x, int32_t y, int32_t pw, int32_t ph, int32_t sp,
    const char *make, const char *model, int32_t tf)
{
    (void)wl; (void)pw; (void)ph; (void)sp; (void)make; (void)model; (void)tf;
    Output *o = data; o->x = x; o->y = y;
}

static void output_mode(void *data, struct wl_output *wl,
    uint32_t flags, int32_t w, int32_t h, int32_t refresh)
{
    (void)wl; (void)refresh;
    Output *o = data;
    if (flags & WL_OUTPUT_MODE_CURRENT) { o->mode_w = w; o->mode_h = h; }
}

static void output_done(void *data, struct wl_output *wl) { (void)data; (void)wl; }

static void output_scale(void *data, struct wl_output *wl, int32_t scale) {
    (void)wl; ((Output *)data)->scale = scale;
}

static void output_name(void *data, struct wl_output *wl, const char *name) {
    (void)wl;
    Output *o = data;
    strncpy(o->name, name ? name : "", sizeof(o->name) - 1);
}

static void output_description(void *data, struct wl_output *wl, const char *desc) {
    (void)data; (void)wl; (void)desc;
}

static const struct wl_output_listener output_listener = {
    .geometry    = output_geometry,
    .mode        = output_mode,
    .done        = output_done,
    .scale       = output_scale,
    .name        = output_name,
    .description = output_description,
};

/* ── xdg_output listeners (override x,y with authoritative logical coords) ── */

static void xdg_output_logical_position(void *data,
    struct zxdg_output_v1 *xdg_out, int32_t x, int32_t y)
{
    (void)xdg_out;
    Output *o = data;
    o->x = x;
    o->y = y;
}

static void xdg_output_logical_size(void *data,
    struct zxdg_output_v1 *xdg_out, int32_t w, int32_t h)
{
    (void)xdg_out;
    Output *o = data;
    o->logical_w = w;
    o->logical_h = h;
}

static void xdg_output_done(void *data, struct zxdg_output_v1 *xdg_out) {
    (void)xdg_out;
    ((Output *)data)->xdg_done = 1;
}

static void xdg_output_name(void *data, struct zxdg_output_v1 *xdg_out, const char *name) {
    (void)xdg_out;
    /* xdg_output name may duplicate wl_output name - only use as fallback */
    Output *o = data;
    if (o->name[0] == '\0' && name)
        strncpy(o->name, name, sizeof(o->name) - 1);
}

static void xdg_output_description(void *data, struct zxdg_output_v1 *xdg_out,
    const char *desc) { (void)data; (void)xdg_out; (void)desc; }

static const struct zxdg_output_v1_listener xdg_output_listener = {
    .logical_position = xdg_output_logical_position,
    .logical_size     = xdg_output_logical_size,
    .done             = xdg_output_done,
    .name             = xdg_output_name,
    .description      = xdg_output_description,
};

/* ── Registry ─────────────────────────────────────────────────────────────── */

static void registry_global(void *data, struct wl_registry *reg,
    uint32_t name, const char *iface, uint32_t version)
{
    State *s = data;
    if (strcmp(iface, wl_shm_interface.name) == 0) {
        s->shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
    } else if (strcmp(iface, zwlr_screencopy_manager_v1_interface.name) == 0) {
        s->screencopy = wl_registry_bind(reg, name,
            &zwlr_screencopy_manager_v1_interface, version < 3 ? version : 3);
    } else if (strcmp(iface, zxdg_output_manager_v1_interface.name) == 0) {
        s->xdg_output_manager = wl_registry_bind(reg, name,
            &zxdg_output_manager_v1_interface, version < 3 ? version : 3);
    } else if (strcmp(iface, wl_output_interface.name) == 0 && s->n_outputs < MAX_OUTPUTS) {
        Output *o = &s->outputs[s->n_outputs++];
        memset(o, 0, sizeof(*o));
        o->scale = 1;
        o->wl = wl_registry_bind(reg, name, &wl_output_interface, version < 4 ? version : 4);
        wl_output_add_listener(o->wl, &output_listener, o);
    }
}

static void registry_global_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data; (void)reg; (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global        = registry_global,
    .global_remove = registry_global_remove,
};

/* ── PNG write ────────────────────────────────────────────────────────────── */

/* Write BGRA or RGBA pixel data as PNG.
 * For BGRA (ARGB8888 / XRGB8888 in LE memory), swap B↔R.
 * For RGBA (ABGR8888 / XBGR8888 in LE memory), bytes are already R,G,B,A - no swap.
 * Pass y_invert=1 when the ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT flag is set. */
static int write_png_bgra(const char *path, const uint8_t *data,
    uint32_t width, uint32_t height, uint32_t stride, int y_invert, int already_rgb)
{
    FILE *fp = fopen(path, "wb");
    if (!fp) { perror(path); return -1; }

    png_structp png  = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    png_infop   info = png_create_info_struct(png);
    if (!png || !info) { fclose(fp); return -1; }

    if (setjmp(png_jmpbuf(png))) {
        png_destroy_write_struct(&png, &info); fclose(fp); return -1;
    }

    png_init_io(png, fp);
    png_set_IHDR(png, info, width, height, 8, PNG_COLOR_TYPE_RGBA,
        PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    png_write_info(png, info);

    uint8_t *row = malloc(stride);
    if (!row) { png_destroy_write_struct(&png, &info); fclose(fp); return -1; }

    for (uint32_t y = 0; y < height; y++) {
        uint32_t sy = y_invert ? (height - 1 - y) : y;
        memcpy(row, data + (size_t)sy * stride, stride);
        if (!already_rgb) {
            for (uint32_t x = 0; x < width; x++) {
                uint8_t b = row[x * 4];
                row[x * 4]     = row[x * 4 + 2];
                row[x * 4 + 2] = b;
            }
        }
        png_write_row(png, row);
    }
    free(row);

    png_write_end(png, NULL);
    png_destroy_write_struct(&png, &info);
    fclose(fp);
    return 0;
}

/* ── Core capture ─────────────────────────────────────────────────────────── */

static int do_capture(State *state, struct zwlr_screencopy_frame_v1 *frame_obj, Frame *frame) {
    memset(frame, 0, sizeof(*frame));
    frame->state = state;
    frame->fd    = -1;
    zwlr_screencopy_frame_v1_add_listener(frame_obj, &frame_listener, frame);
    wl_display_flush(state->display);

    uint32_t ver = zwlr_screencopy_frame_v1_get_version(frame_obj);

    if (ver >= 3) {
        /* frame_ev_buffer_done allocates the buffer and calls copy */
        while (frame->done == 0) {
            if (wl_display_dispatch(state->display) < 0) return -1;
        }
    } else {
        /* v1/v2: send copy after receiving the wl_shm buffer event */
        while (!frame->shm_received && frame->done == 0) {
            if (wl_display_dispatch(state->display) < 0) return -1;
        }
        if (frame->done != 0) return frame->done == 1 ? 0 : -1;
        frame->buffer = alloc_shm_buffer(frame);
        if (!frame->buffer) return -1;
        zwlr_screencopy_frame_v1_copy(frame_obj, frame->buffer);
        while (frame->done == 0) {
            if (wl_display_dispatch(state->display) < 0) return -1;
        }
    }

    return frame->done == 1 ? 0 : -1;
}

/* ── Capture variants ─────────────────────────────────────────────────────── */

static int capture_output(State *state, Output *out, int cursor, const char *path) {
    struct zwlr_screencopy_frame_v1 *fo =
        zwlr_screencopy_manager_v1_capture_output(state->screencopy, cursor, out->wl);
    Frame f;
    int rc = do_capture(state, fo, &f);
    if (rc == 0) {
        int inv = (f.flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT) != 0;
        rc = write_png_bgra(path, f.data, f.width, f.height, f.stride, inv, f.bgr_order);
    } else {
        fprintf(stderr, "capture failed for output %s\n", out->name);
    }
    zwlr_screencopy_frame_v1_destroy(fo);
    frame_cleanup(&f);
    return rc;
}

static int capture_region(State *state,
    int32_t gx, int32_t gy, int32_t gw, int32_t gh,
    int cursor, const char *path)
{
    /* Find the output that contains the region origin in compositor space.
     * Prefer xdg-output logical dimensions (logical_w/h) when available,
     * fall back to mode_w/scale for compositors without xdg-output. */
    Output *tgt = NULL;
    for (int i = 0; i < state->n_outputs; i++) {
        Output *o = &state->outputs[i];
        int32_t lw = (o->xdg_done && o->logical_w > 0) ? o->logical_w
                     : (o->scale > 0 ? o->mode_w / o->scale : o->mode_w);
        int32_t lh = (o->xdg_done && o->logical_h > 0) ? o->logical_h
                     : (o->scale > 0 ? o->mode_h / o->scale : o->mode_h);
        if (gx >= o->x && gx < o->x + lw && gy >= o->y && gy < o->y + lh) {
            tgt = o; break;
        }
    }
    if (!tgt) tgt = &state->outputs[0];

    /* Translate global coords to output-local logical coordinates */
    struct zwlr_screencopy_frame_v1 *fo =
        zwlr_screencopy_manager_v1_capture_output_region(
            state->screencopy, cursor, tgt->wl,
            gx - tgt->x, gy - tgt->y, gw, gh);
    Frame f;
    int rc = do_capture(state, fo, &f);
    if (rc == 0) {
        int inv = (f.flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT) != 0;
        rc = write_png_bgra(path, f.data, f.width, f.height, f.stride, inv, f.bgr_order);
    } else {
        fprintf(stderr, "region capture failed\n");
    }
    zwlr_screencopy_frame_v1_destroy(fo);
    frame_cleanup(&f);
    return rc;
}

static int capture_all(State *state, int cursor, const char *path) {
    int n = state->n_outputs;
    if (n == 0) { fprintf(stderr, "no outputs\n"); return -1; }
    if (n == 1) return capture_output(state, &state->outputs[0], cursor, path);

    struct zwlr_screencopy_frame_v1 *fobjs[MAX_OUTPUTS];
    Frame frames[MAX_OUTPUTS];
    memset(frames, 0, sizeof(frames));

    for (int i = 0; i < n; i++) {
        fobjs[i] = zwlr_screencopy_manager_v1_capture_output(
            state->screencopy, cursor, state->outputs[i].wl);
        if (do_capture(state, fobjs[i], &frames[i]) < 0) {
            fprintf(stderr, "capture failed for output %d\n", i);
            for (int j = 0; j <= i; j++) {
                zwlr_screencopy_frame_v1_destroy(fobjs[j]);
                frame_cleanup(&frames[j]);
            }
            return -1;
        }
    }

    /* Sort index by logical X so outputs are arranged left-to-right */
    int order[MAX_OUTPUTS];
    for (int i = 0; i < n; i++) order[i] = i;
    for (int i = 0; i < n - 1; i++)
        for (int j = 0; j < n - 1 - i; j++)
            if (state->outputs[order[j]].x > state->outputs[order[j + 1]].x) {
                int t = order[j]; order[j] = order[j + 1]; order[j + 1] = t;
            }

    uint32_t total_w = 0, total_h = 0;
    for (int i = 0; i < n; i++) {
        total_w += frames[i].width;
        if (frames[i].height > total_h) total_h = frames[i].height;
    }

    uint32_t canvas_stride = total_w * 4;
    uint8_t *canvas = calloc(total_h, canvas_stride);
    if (!canvas) {
        for (int i = 0; i < n; i++) {
            zwlr_screencopy_frame_v1_destroy(fobjs[i]);
            frame_cleanup(&frames[i]);
        }
        return -1;
    }

    uint32_t x_off = 0;
    for (int oi = 0; oi < n; oi++) {
        int i = order[oi];
        Frame *f = &frames[i];
        int inv = (f->flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT) != 0;
        for (uint32_t y = 0; y < f->height && y < total_h; y++) {
            uint32_t sy = inv ? (f->height - 1 - y) : y;
            memcpy(canvas + (size_t)y * canvas_stride + x_off * 4,
                   (const uint8_t *)f->data + (size_t)sy * f->stride, f->width * 4);
        }
        x_off += f->width;
    }

    /* For multi-monitor canvas, swap bytes matching the first output's format */
    int canvas_bgr = (n > 0) ? frames[0].bgr_order : 0;
    int rc = write_png_bgra(path, canvas, total_w, total_h, canvas_stride, 0, canvas_bgr);
    free(canvas);
    for (int i = 0; i < n; i++) {
        zwlr_screencopy_frame_v1_destroy(fobjs[i]);
        frame_cleanup(&frames[i]);
    }
    return rc;
}

/* ── main ─────────────────────────────────────────────────────────────────── */

int main(int argc, char *argv[]) {
    const char *output_name = NULL, *geometry = NULL, *out_file = NULL;
    int cursor = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-c") == 0) {
            cursor = 1;
        } else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            output_name = argv[++i];
        } else if (strcmp(argv[i], "-g") == 0 && i + 1 < argc) {
            geometry = argv[++i];
        } else if (argv[i][0] != '-') {
            out_file = argv[i];
        } else {
            fprintf(stderr, "usage: singularity-screenshot [-c] [-o output] [-g \"x,y WxH\"] <file.png>\n");
            return 1;
        }
    }

    if (!out_file) {
        fprintf(stderr, "usage: singularity-screenshot [-c] [-o output] [-g \"x,y WxH\"] <file.png>\n");
        return 1;
    }

    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "failed to connect to Wayland display\n"); return 1; }

    State state = {0};
    state.display = display;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, &state);
    wl_display_roundtrip(display); /* enumerate globals */
    wl_display_roundtrip(display); /* flush output events (geometry, mode, scale, name) */

    /* Create xdg_output for each wl_output to get authoritative logical positions */
    struct zxdg_output_v1 *xdg_outs[MAX_OUTPUTS] = {0};
    if (state.xdg_output_manager) {
        for (int i = 0; i < state.n_outputs; i++) {
            xdg_outs[i] = zxdg_output_manager_v1_get_xdg_output(
                state.xdg_output_manager, state.outputs[i].wl);
            zxdg_output_v1_add_listener(xdg_outs[i], &xdg_output_listener, &state.outputs[i]);
        }
        wl_display_roundtrip(display); /* flush xdg-output events */
    }

    if (!state.shm || !state.screencopy || state.n_outputs == 0) {
        fprintf(stderr, "required Wayland interfaces not available\n");
        wl_display_disconnect(display);
        return 1;
    }

    int ret;
    if (geometry) {
        int32_t gx, gy, gw, gh;
        if (sscanf(geometry, "%d,%d %dx%d", &gx, &gy, &gw, &gh) != 4) {
            fprintf(stderr, "invalid geometry: '%s'  (expected x,y WxH)\n", geometry);
            wl_display_disconnect(display);
            return 1;
        }
        ret = capture_region(&state, gx, gy, gw, gh, cursor, out_file);
    } else if (output_name) {
        Output *tgt = NULL;
        for (int i = 0; i < state.n_outputs; i++)
            if (strcmp(state.outputs[i].name, output_name) == 0) {
                tgt = &state.outputs[i]; break;
            }
        if (!tgt) {
            fprintf(stderr, "output '%s' not found\n", output_name);
            wl_display_disconnect(display);
            return 1;
        }
        ret = capture_output(&state, tgt, cursor, out_file);
    } else {
        ret = capture_all(&state, cursor, out_file);
    }

    for (int i = 0; i < state.n_outputs; i++) {
        if (xdg_outs[i]) zxdg_output_v1_destroy(xdg_outs[i]);
        wl_output_destroy(state.outputs[i].wl);
    }
    if (state.xdg_output_manager) zxdg_output_manager_v1_destroy(state.xdg_output_manager);
    zwlr_screencopy_manager_v1_destroy(state.screencopy);
    wl_shm_destroy(state.shm);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    return ret == 0 ? 0 : 1;
}
