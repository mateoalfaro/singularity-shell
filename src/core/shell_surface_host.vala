using Gtk;
using GtkLayerShell;

namespace Singularity {

    /**
     * Shell-owned layer-shell window that hosts a plugin's content widget in
     * CONTENT_INJECTION mode. The shell keeps ownership of anchoring,
     * exclusive zone and the monitor binding; the plugin only supplies the
     * widget. This is how a plugin can replace e.g. the dock's look without
     * reimplementing the layer-shell plumbing.
     */
    public class ShellSurfaceHost : Gtk.Window {
        public ShellSurfaceHost(Gtk.Application app, ShellSurfaceProvider provider,
                                Gdk.Monitor monitor) {
            Object(application: app);
            add_css_class("singularity");
            add_css_class("singularity-shell");

            init_for_window(this);
            GtkLayerShell.set_monitor(this, monitor);
            set_layer(this, GtkLayerShell.Layer.OVERLAY);

            apply_anchor(provider.anchor);

            var content = provider.create_content(monitor);
            if (content != null) set_child(content);

            present();
        }

        private void apply_anchor(ShellSurfaceAnchor a) {
            switch (a) {
                case ShellSurfaceAnchor.BOTTOM:
                    set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
                    set_exclusive_zone(this, 0);
                    break;
                case ShellSurfaceAnchor.TOP:
                    set_anchor(this, GtkLayerShell.Edge.TOP, true);
                    set_anchor(this, GtkLayerShell.Edge.LEFT, true);
                    set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
                    auto_exclusive_zone_enable(this);
                    break;
                case ShellSurfaceAnchor.LEFT:
                    set_anchor(this, GtkLayerShell.Edge.LEFT, true);
                    set_anchor(this, GtkLayerShell.Edge.TOP, true);
                    set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
                    set_exclusive_zone(this, 0);
                    break;
                case ShellSurfaceAnchor.RIGHT:
                    set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
                    set_anchor(this, GtkLayerShell.Edge.TOP, true);
                    set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
                    set_exclusive_zone(this, 0);
                    break;
                case ShellSurfaceAnchor.FULLSCREEN:
                    set_anchor(this, GtkLayerShell.Edge.TOP, true);
                    set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
                    set_anchor(this, GtkLayerShell.Edge.LEFT, true);
                    set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
                    set_exclusive_zone(this, -1);
                    break;
            }
        }
    }
}
