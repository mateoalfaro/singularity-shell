[CCode (cheader_filename = "lock_surface.h")]
namespace Singularity.Lock {
    [CCode (has_target = false)]
    public delegate void LockedCallback(void* data);
    [CCode (has_target = false)]
    public delegate void FinishedCallback(void* data);

    [CCode (cname = "singularity_lock_screen")]
    public int lock_screen(Gtk.Widget widget, LockedCallback on_locked, FinishedCallback on_finished, void* user_data);

    [CCode (cname = "singularity_lock_get_lock_surface")]
    public void* get_lock_surface(Gtk.Widget widget);

    [CCode (cname = "singularity_unlock_and_destroy")]
    public void unlock_and_destroy();
}

[CCode (cheader_filename = "pam_auth.h")]
namespace Singularity.Pam {
    [CCode (cname = "singularity_pam_authenticate")]
    public int authenticate(string username, string password);
}