// singularity-keyboard-reset: fixes zombie EXCLUSIVE layer surfaces in labwc.
//
// When a Wayland client (e.g. slurp) exits abruptly without unmapping its
// EXCLUSIVE layer-shell surfaces, labwc's seat->focused_layer stays pointing
// at the dead surfaces and blocks all keybinds.
//
// This tool creates a new EXCLUSIVE surface, then closes it properly via GTK
// (which sends a real wl_surface unmap before disconnect). That triggers
// labwc's handle_unmap, try_to_focus_next_layer_or_toplevel(), which finds
// no remaining EXCLUSIVE surfaces and restores keyboard focus.
using Gtk;
using GtkLayerShell;

void main() {
    Gtk.init();
    var win = new Gtk.Window();
    GtkLayerShell.init_for_window(win);
    GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY);
    GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.EXCLUSIVE);
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.TOP, true);
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, true);
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT, true);
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT, true);
    GtkLayerShell.set_exclusive_zone(win, -1);
    win.present();

    var loop = new GLib.MainLoop();
    // Wait two frames so the surface is committed/mapped in labwc,
    // then destroy it properly so handle_unmap fires in the compositor.
    GLib.Timeout.add(200, () => {
        win.destroy();
        loop.quit();
        return GLib.Source.REMOVE;
    });
    loop.run();
}
