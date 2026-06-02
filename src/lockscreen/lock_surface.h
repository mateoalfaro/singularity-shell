#ifndef LOCK_SURFACE_H
#define LOCK_SURFACE_H

#include <gtk/gtk.h>

typedef void (*LockLockedCallback)(void *user_data);
typedef void (*LockFinishedCallback)(void *user_data);

int  singularity_lock_screen(GtkWidget *widget, LockLockedCallback on_locked,
                             LockFinishedCallback on_finished, void *user_data);
void *singularity_lock_get_lock_surface(GtkWidget *widget);
void  singularity_unlock_and_destroy(void);

#endif