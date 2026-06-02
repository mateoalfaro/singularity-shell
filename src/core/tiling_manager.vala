using Singularity;
using GLib;

namespace Singularity {

    public class TilingManager : Object {
        private AppSystem app_system;
        private GLib.Settings settings;
        private bool enabled = true;
        public static const uint SNAP_NONE = 0;
        public static const uint SNAP_LEFT = 1;
        public static const uint SNAP_RIGHT = 2;
        public static const uint SNAP_TOP = 3;
        public static const uint SNAP_BOTTOM = 4;
        public static const uint SNAP_TOP_LEFT = 5;
        public static const uint SNAP_TOP_RIGHT = 6;
        public static const uint SNAP_BOTTOM_LEFT = 7;
        public static const uint SNAP_BOTTOM_RIGHT = 8;
        public static const uint SNAP_MAXIMIZE = 9;

        public TilingManager(AppSystem app_system) {
            this.app_system = app_system;
            settings = new GLib.Settings("dev.sinty.desktop");
            enabled = settings.get_boolean("tiling-enabled");
            settings.changed["tiling-enabled"].connect(() => {
                enabled = settings.get_boolean("tiling-enabled");
                if (enabled) schedule_apply_layout();
            });
            app_system.app_opened.connect(on_app_opened);
            app_system.app_closed.connect(on_app_closed);
            app_system.workspaces_changed.connect(on_workspaces_changed);
            app_system.app_focused.connect(on_app_focused);
        }
        private uint _apply_timeout_id = 0;

        private void schedule_apply_layout() {
            if (_apply_timeout_id != 0) GLib.Source.remove(_apply_timeout_id);
            _apply_timeout_id = GLib.Timeout.add(100, () => {
                _apply_timeout_id = 0;
                apply_layout();
                return Source.REMOVE;
            }, GLib.Priority.DEFAULT_IDLE);
        }

        private void on_app_opened(void* handle, string app_id) {
            if (!enabled) return;
            schedule_apply_layout();
        }

        private void on_app_closed(void* handle) {
            if (!enabled) return;
            schedule_apply_layout();
        }

        private void on_workspaces_changed() {
            if (!enabled) return;
            schedule_apply_layout();
        }

        private void on_app_focused(string? app_id) {
            if (!enabled) return;
            schedule_apply_layout();
        }

        private void snap(AppSystem.Window win, uint s) {
            Singularity.wayland_snap_view(win.handle, s);
            win.snap_type = s;
        }

        public void apply_layout() {
            var windows = app_system.get_active_workspace_windows();
            var tileable = new List<AppSystem.Window>();
            foreach (var w in windows) {
                if (w.app_id == null || w.app_id == "unknown-wayland-surface")
                    continue;
                if (w.app_id.has_prefix("chrome-") || w.app_id.contains(".flextop.chrome-"))
                    continue;
                tileable.append(w);
            }
            int count = (int)tileable.length();
            if (count == 0) return;
            if (count == 1) {
                snap(tileable.nth_data(0), SNAP_MAXIMIZE);
            }
            else if (count == 2) {
                snap(tileable.nth_data(0), SNAP_LEFT);
                snap(tileable.nth_data(1), SNAP_RIGHT);
            }
            else if (count == 3) {
                snap(tileable.nth_data(0), SNAP_LEFT);
                snap(tileable.nth_data(1), SNAP_TOP_RIGHT);
                snap(tileable.nth_data(2), SNAP_BOTTOM_RIGHT);
            }
            else {
                int i = 0;
                foreach (var win in tileable) {
                    uint s = SNAP_NONE;
                    if (i == 0) s = SNAP_TOP_LEFT;
                    else if (i == 1) s = SNAP_TOP_RIGHT;
                    else if (i == 2) s = SNAP_BOTTOM_LEFT;
                    else if (i == 3) s = SNAP_BOTTOM_RIGHT;
                    else s = SNAP_MAXIMIZE;
                    snap(win, s);
                    i++;
                }
            }
        }
    }
}
