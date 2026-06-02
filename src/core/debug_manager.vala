namespace Singularity {

    /**
     * Central debug/instrumentation hub for Singularity Desktop.
     *
     * Toggle debug_mode at runtime (from DeveloperPage or CLI) to enable
     * verbose logging and activate per-subsystem debug tools.
     */
    public class DebugManager : Object {

        private static DebugManager? _instance = null;

        /** Master debug mode switch. */
        public bool debug_mode { get; set; default = false; }

        /** Whether the floating HUD overlay is visible. */
        public bool hud_visible { get; set; default = false; }

        /**
         * Weak references to non-singleton managers set by main.vala
         * after those managers are created.
         */
        public weak HotCornerManager? hot_corner_manager { get; set; }
        public weak TilingManager? tiling_manager { get; set; }

        /** Whether the sidebar should stay open when focus is lost. */
        public bool sidebar_pinned { get; set; default = false; }
        /** Whether the apps overview should stay open when focus is lost. */
        public bool overview_pinned { get; set; default = false; }
        /** Whether the workspaces overview should stay open when focus is lost. */
        public bool workspaces_pinned { get; set; default = false; }
        public signal void log_message (string module, string level, string message);

        public static DebugManager get_default () {
            if (_instance == null)
                _instance = new DebugManager ();
            return _instance;
        }

        private DebugManager () {}

        /**
         * Emit a debug log entry.
         * Only active when debug_mode is true; otherwise a no-op so callers
         * can leave the calls in place without performance cost.
         */
        public void log (string module, string level, string message) {
            if (!debug_mode) return;
            var ts = new DateTime.now_local ().format ("%H:%M:%S");
            GLib.message ("[%s][%s][%s] %s", ts, level.up (), module, message);
            log_message (module, level, message);
        }
    }
}
