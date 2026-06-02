using GLib;

public class ExtremeModeManager : Object {
    private static ExtremeModeManager? _instance;
    private GLib.Settings _settings;

    public bool active { get; private set; }
    public signal void extreme_mode_changed ();

    public static ExtremeModeManager get_default () {
        if (_instance == null) _instance = new ExtremeModeManager ();
        return _instance;
    }

    private ExtremeModeManager () {
        _settings = new GLib.Settings ("dev.sinty.desktop");
        active = _settings.get_boolean ("extreme-mode-active");

        _settings.changed["extreme-mode-active"].connect (() => {
            var new_state = _settings.get_boolean ("extreme-mode-active");
            if (new_state != active) {
                active = new_state;
                if (active) _enable ();
                else        _disable ();
                extreme_mode_changed ();
            }
        });
    }

    public void set_extreme_mode (bool enabled) {
        if (enabled == active) return;
        _settings.set_boolean ("extreme-mode-active", enabled);
    }

    public void toggle_extreme_mode () {
        set_extreme_mode (!active);
    }

    private void _enable () {
        // Save current brightness
        var bri = Singularity.BrightnessManager.get_default ();
        _settings.set_double ("extreme-mode-saved-brightness", bri.brightness);

        // Save current dark mode
        bool cur_dark = _settings.get_boolean ("dark-mode");
        _settings.set_boolean ("extreme-mode-saved-dark-mode", cur_dark);

        // Save animations
        var gtk_s = Gtk.Settings.get_default ();
        _settings.set_boolean ("extreme-mode-saved-animations", gtk_s.gtk_enable_animations);

        // Apply: force dark mode
        _settings.set_boolean ("dark-mode", true);

        // Apply: 10% brightness
        bri.set_level (10.0);

        // Apply: disable animations
        gtk_s.gtk_enable_animations = false;
    }

    private void _disable () {
        // Restore brightness
        var bri = Singularity.BrightnessManager.get_default ();
        double saved_bri = _settings.get_double ("extreme-mode-saved-brightness");
        bri.set_level (saved_bri);

        // Restore dark mode
        bool saved_dark = _settings.get_boolean ("extreme-mode-saved-dark-mode");
        _settings.set_boolean ("dark-mode", saved_dark);

        // Restore animations
        bool saved_anim = _settings.get_boolean ("extreme-mode-saved-animations");
        Gtk.Settings.get_default ().gtk_enable_animations = saved_anim;
    }
}
