using Gtk;
using GtkLayerShell;

namespace Singularity {

    public class MonitorOsd : Object {
        private Gtk.Window[] _osds = {};

        public void show(Gtk.Application app, GLib.List<DisplayManager.Monitor> monitors) {
            hide();
            int idx = 0;
            foreach (var mon in monitors) {
                if (!mon.enabled) { idx++; continue; }
                var win = new Gtk.Window();
                win.set_application(app);
                GtkLayerShell.init_for_window(win);
                GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY);
                GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.TOP, false);
                GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, false);
                GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT, false);
                GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT, false);
                var gdk_mon = find_gdk_monitor_by_name(mon.name);
                if (gdk_mon != null) GtkLayerShell.set_monitor(win, gdk_mon);
                win.add_css_class("singularity");
                win.add_css_class("monitor-osd");
                var lbl = new Gtk.Label((idx + 1).to_string());
                lbl.add_css_class("monitor-osd-number");
                win.set_child(lbl);
                win.present();
                _osds += win;
                idx++;
            }
        }

        public void hide() {
            foreach (var w in _osds) w.close();
            _osds = {};
        }

        private Gdk.Monitor? find_gdk_monitor_by_name(string name) {
            var display = Gdk.Display.get_default();
            if (display == null) return null;
            var mons = display.get_monitors();
            uint n = mons.get_n_items();
            for (uint i = 0; i < n; i++) {
                var mon = (Gdk.Monitor) mons.get_item(i);
                if (mon.get_connector() == name) return mon;
            }
            return null;
        }
    }
}
