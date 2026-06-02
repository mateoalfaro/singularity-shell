#define _POSIX_C_SOURCE 200809L
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>
#include <gtk/gtk.h>

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/wayland/gdkwayland.h>
#endif

#include "ext-session-lock-v1-client-protocol.h"
#include "lock_surface.h"

#ifdef GDK_WINDOWING_WAYLAND

static struct ext_session_lock_manager_v1 *cached_lock_manager = NULL;
static struct wl_display *cached_wl_display = NULL;

static struct ext_session_lock_v1 *active_lock = NULL;
static LockLockedCallback locked_cb = NULL;
static LockFinishedCallback finished_cb = NULL;
static void *lock_user_data = NULL;

static void
lock_locked(void *data, struct ext_session_lock_v1 *lock)
{
    g_message("singularity_lock: LOCKED event received from compositor");
    if (locked_cb)
        locked_cb(lock_user_data);
}

static void
lock_finished(void *data, struct ext_session_lock_v1 *lock)
{
    g_message("singularity_lock: FINISHED event received");
    active_lock = NULL;
    if (finished_cb)
        finished_cb(lock_user_data);
}

static const struct ext_session_lock_v1_listener lock_listener = {
    .locked = lock_locked,
    .finished = lock_finished,
};

static void
lock_surface_configure(void *data, struct ext_session_lock_surface_v1 *surface,
                       uint32_t serial, uint32_t width, uint32_t height)
{
    ext_session_lock_surface_v1_ack_configure(surface, serial);
}

static const struct ext_session_lock_surface_v1_listener lock_surface_listener = {
    .configure = lock_surface_configure,
};

static void
registry_global(void *data, struct wl_registry *registry, uint32_t name,
                const char *interface, uint32_t version)
{
    struct ext_session_lock_manager_v1 **manager = data;
    if (strcmp(interface, ext_session_lock_manager_v1_interface.name) == 0) {
        *manager = wl_registry_bind(registry, name,
            &ext_session_lock_manager_v1_interface, 1);
    }
}

static void
registry_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static struct ext_session_lock_manager_v1 *
get_lock_manager(struct wl_display *wl_display)
{
    if (wl_display == cached_wl_display)
        return cached_lock_manager;

    struct ext_session_lock_manager_v1 *manager = NULL;
    struct wl_registry *registry = wl_display_get_registry(wl_display);
    wl_registry_add_listener(registry, &registry_listener, &manager);
    wl_display_roundtrip(wl_display);
    wl_registry_destroy(registry);

    cached_wl_display = wl_display;
    cached_lock_manager = manager;
    return manager;
}

#endif /* GDK_WINDOWING_WAYLAND */

int
singularity_lock_screen(GtkWidget *widget, LockLockedCallback on_locked,
                        LockFinishedCallback on_finished, void *user_data)
{
#ifdef GDK_WINDOWING_WAYLAND
    g_message("singularity_lock_screen: starting");
    GdkDisplay *gdk_display = gtk_widget_get_display(widget);
    if (!GDK_IS_WAYLAND_DISPLAY(gdk_display)) {
        g_warning("singularity_lock_screen: not a Wayland display");
        return -1;
    }

    struct wl_display *wl_display =
        gdk_wayland_display_get_wl_display(GDK_WAYLAND_DISPLAY(gdk_display));
    struct ext_session_lock_manager_v1 *manager = get_lock_manager(wl_display);
    if (!manager) {
        g_warning("singularity_lock_screen: ext_session_lock_manager_v1 not available");
        return -1;
    }

    g_message("singularity_lock_screen: requesting lock");
    locked_cb = on_locked;
    finished_cb = on_finished;
    lock_user_data = user_data;

    active_lock = ext_session_lock_manager_v1_lock(manager);
    ext_session_lock_v1_add_listener(active_lock, &lock_listener, NULL);

    wl_display_roundtrip(wl_display);
    g_message("singularity_lock_screen: lock requested, roundtrip done");
    return 0;
#else
    g_warning("singularity_lock_screen: not built with Wayland support");
    return -1;
#endif
}

void *
singularity_lock_get_lock_surface(GtkWidget *widget)
{
#ifdef GDK_WINDOWING_WAYLAND
    if (!active_lock)
        return NULL;

    GdkSurface *gdk_surface = gtk_native_get_surface(GTK_NATIVE(widget));
    if (!gdk_surface || !GDK_IS_WAYLAND_SURFACE(gdk_surface))
        return NULL;

    struct wl_surface *wl_surface =
        gdk_wayland_surface_get_wl_surface(GDK_WAYLAND_SURFACE(gdk_surface));
    if (!wl_surface)
        return NULL;

    GdkMonitor *gdk_monitor = g_object_get_data(G_OBJECT(widget), "lock-monitor");
    if (!gdk_monitor)
        return NULL;

    struct wl_output *wl_output =
        gdk_wayland_monitor_get_wl_output(gdk_monitor);

    struct ext_session_lock_surface_v1 *lock_surface =
        ext_session_lock_v1_get_lock_surface(active_lock, wl_surface, wl_output);
    ext_session_lock_surface_v1_add_listener(lock_surface, &lock_surface_listener, NULL);

    return lock_surface;
#else
    return NULL;
#endif
}

void
singularity_unlock_and_destroy(void)
{
#ifdef GDK_WINDOWING_WAYLAND
    if (active_lock) {
        ext_session_lock_v1_unlock_and_destroy(active_lock);
        active_lock = NULL;
    }
#endif
}