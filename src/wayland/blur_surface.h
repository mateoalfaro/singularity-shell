#ifndef BLUR_SURFACE_H
#define BLUR_SURFACE_H

#include <stdint.h>
#include <gtk/gtk.h>

/*
 * Request compositor-level background blur for a GTK window surface.
 *
 * @widget: a realized GtkWidget (typically the top-level window)
 * @radius: blur radius in pixels; 0 disables blur
 *
 * No-op if the compositor does not advertise the
 * zsingularity_blur_manager_v1 protocol or if GTK is not running
 * on a Wayland backend.
 */
void singularity_request_surface_blur(GtkWidget *widget, uint32_t radius);
void singularity_surface_set_input_passthrough(GtkWidget *widget);

#endif /* BLUR_SURFACE_H */
