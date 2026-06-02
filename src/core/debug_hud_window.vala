using Gtk;

namespace Singularity {

    /**
     * Floating HUD overlay shown above all shell surfaces.
     *
     * Displays shell-specific diagnostics: focused app, Wayland window count,
     * shell frame rate, total GTK widget count across all shell windows, and
     * the widget count of the currently active GTK window.
     * The window is fully click-through (empty input region).
     */
    public class DebugHudWindow : Gtk.Window {

        private Label _app_lbl;
        private Label _wins_lbl;
        private Label _running_lbl;
        private Label _fps_lbl;
        private Label _total_widgets_lbl;
        private Label _active_win_lbl;
        private uint  _timer_id = 0;

        /* Kept so refresh() can iterate application windows. */
        private unowned Gtk.Application _app;

        public DebugHudWindow (Gtk.Application app) {
            Object (application: app);
            _app = app;

            GtkLayerShell.init_for_window (this);
            GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP,    true);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT,  true);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, false);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT,   false);
            GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP,   52);
            GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, 12);

            add_css_class ("debug-hud");

            var outer = new Box (Orientation.VERTICAL, 6);
            outer.margin_top    = 10;
            outer.margin_bottom = 10;
            outer.margin_start  = 14;
            outer.margin_end    = 14;

            var title = new Label (_("Debug HUD"));
            title.add_css_class ("debug-hud-title");
            title.halign = Align.START;
            outer.append (title);

            outer.append (new Separator (Orientation.HORIZONTAL));

            _app_lbl          = make_row ("Focused app",       "-");
            _wins_lbl         = make_row ("Wayland wins",       "0");
            _running_lbl      = make_row ("Running apps",       "0");
            _fps_lbl          = make_row ("Shell FPS",          "-");
            _total_widgets_lbl = make_row ("Shell widgets",     "-");
            _active_win_lbl   = make_row ("Active win widgets", "-");

            foreach (var lbl in new Label[] {
                    _app_lbl, _wins_lbl, _running_lbl,
                    _fps_lbl, _total_widgets_lbl, _active_win_lbl })
                outer.append (lbl);

            set_child (outer);

            map.connect_after (() => {
                unowned var surf = get_surface ();
                if (surf != null)
                    surf.set_input_region (new Cairo.Region ());
            });
        }

        private Label make_row (string key, string value) {
            var lbl = new Label (_("%s: %s").printf (key, value));
            lbl.add_css_class ("debug-hud-row");
            lbl.halign = Align.START;
            lbl.set_use_markup (false);
            return lbl;
        }

        private void set_row (Label lbl, string key, string value) {
            lbl.set_text ("%s: %s".printf (key, value));
        }

        /* Recursively count every GTK widget in a subtree. */
        private int count_widgets (Gtk.Widget root) {
            int n = 1;
            var child = root.get_first_child ();
            while (child != null) {
                n += count_widgets (child);
                child = child.get_next_sibling ();
            }
            return n;
        }

        public void start_updates () {
            refresh ();
            if (_timer_id != 0) return;
            _timer_id = Timeout.add (1000, () => {
                refresh ();
                return Source.CONTINUE;
            });
        }

        public void stop_updates () {
            if (_timer_id != 0) {
                Source.remove (_timer_id);
                _timer_id = 0;
            }
        }

        private void refresh () {
            var as_sys = AppSystem.get_default ();
            set_row (_app_lbl,     "Focused app",  as_sys.get_focused_app_id () ?? "-");
            set_row (_wins_lbl,    "Wayland wins",  as_sys.get_windows ().length ().to_string ());
            set_row (_running_lbl, "Running apps",  as_sys.get_running_apps ().length ().to_string ());

            // FPS from this window's own frame clock
            var clock = get_frame_clock ();
            set_row (_fps_lbl, "Shell FPS",
                clock != null ? "%.1f".printf (clock.get_fps ()) : "-");

            // Total GTK widget count across all shell windows (excluding the HUD itself)
            int total = 0;
            foreach (var win in _app.get_windows ())
                if (win != this)
                    total += count_widgets (win);
            set_row (_total_widgets_lbl, "Shell widgets", total.to_string ());

            // Widget count for the currently focused GTK window (excluding the HUD)
            var active = _app.get_active_window ();
            if (active == this) active = null;
            set_row (_active_win_lbl, "Active win widgets",
                active != null ? count_widgets (active).to_string () : "-");
        }

        protected override void dispose () {
            stop_updates ();
            base.dispose ();
        }
    }
}
