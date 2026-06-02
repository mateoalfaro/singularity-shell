namespace Singularity {

    // Night light via wlr-gamma-control-unstable-v1 (native Wayland, no external tool).
    // Applies a warm colour temperature ramp directly to each output.
    // Default warm temperature: 4000 K (amber). Neutral is 6500 K.
    public class NightLightManager : GLib.Object {
        public signal void changed();
        public bool enabled { get; private set; default = false; }

        // 4000 K: warm amber similar to elementary Night Light default
        private const int TEMP_WARM = 4000;
        private static NightLightManager? _instance;

        public static NightLightManager get_default() {
            if (_instance == null) _instance = new NightLightManager();
            return _instance;
        }

        public void toggle() {
            if (enabled) disable(); else enable();
        }

        public void enable() {
            if (enabled) return;
            Singularity.wayland_set_night_light(TEMP_WARM);
            enabled = true;
            changed();
        }

        public void disable() {
            if (!enabled) return;
            Singularity.wayland_reset_night_light();
            enabled = false;
            changed();
        }
    }
}
