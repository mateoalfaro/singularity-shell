// singularity-region-picker: GTK4 layer shell region selector
// Replaces slurp - uses NONE keyboard mode to avoid EXCLUSIVE zombie surfaces in labwc.
// Output format: "x,y WxH" (grim-compatible), written to stdout.
using Gtk;
using GtkLayerShell;

class RegionPicker {
    private double sel_start_x = 0;
    private double sel_start_y = 0;
    private double sel_end_x = 0;
    private double sel_end_y = 0;
    private bool active = false;
    private List<SelectionOverlay> overlays = new List<SelectionOverlay>();
    private MainLoop loop;

    public void run() {
        Gtk.init();

        var display = Gdk.Display.get_default();
        if (display == null) {
            stderr.printf("singularity-region-picker: cannot open display\n");
            Posix.exit(1);
        }

        // Transparent window CSS
        var provider = new Gtk.CssProvider();
        provider.load_from_data("window { background-color: transparent; }".data);
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        var monitors = display.get_monitors();
        for (uint i = 0; i < monitors.get_n_items(); i++) {
            var mon = (Gdk.Monitor)monitors.get_item(i);
            var overlay = new SelectionOverlay(this, mon);
            overlays.append(overlay);
            overlay.present();
        }

        loop = new MainLoop();
        loop.run();
    }

    public void on_press(double gx, double gy) {
        sel_start_x = gx;
        sel_start_y = gy;
        sel_end_x = gx;
        sel_end_y = gy;
        active = true;
        redraw_all();
    }

    public void on_motion(double gx, double gy) {
        if (!active) return;
        sel_end_x = gx;
        sel_end_y = gy;
        redraw_all();
    }

    public void on_release(double gx, double gy) {
        if (!active) return;
        active = false;
        sel_end_x = gx;
        sel_end_y = gy;

        double x1 = double.min(sel_start_x, sel_end_x);
        double y1 = double.min(sel_start_y, sel_end_y);
        double x2 = double.max(sel_start_x, sel_end_x);
        double y2 = double.max(sel_start_y, sel_end_y);
        int w = (int)(x2 - x1);
        int h = (int)(y2 - y1);

        if (w > 5 && h > 5) {
            stdout.printf("%d,%d %dx%d\n", (int)x1, (int)y1, w, h);
            stdout.flush();
            Posix.exit(0);
        } else {
            Posix.exit(1);
        }
    }

    public void cancel() { Posix.exit(1); }

    // Getters for overlay drawing
    public bool   is_active  { get { return active; } }
    public double start_x    { get { return sel_start_x; } }
    public double start_y    { get { return sel_start_y; } }
    public double end_x      { get { return sel_end_x; } }
    public double end_y      { get { return sel_end_y; } }

    private void redraw_all() {
        foreach (var o in overlays) o.queue_redraw();
    }
}

class SelectionOverlay : Gtk.Window {
    private RegionPicker picker;
    private Gdk.Rectangle geo;
    private DrawingArea da;

    public SelectionOverlay(RegionPicker p, Gdk.Monitor mon) {
        Object();
        picker = p;
        geo = mon.get_geometry();

        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.OVERLAY);
        GtkLayerShell.set_monitor(this, mon);
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.NONE);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
        GtkLayerShell.set_exclusive_zone(this, -1);

        da = new DrawingArea();
        da.set_draw_func(on_draw);
        da.hexpand = true;
        da.vexpand = true;
        da.set_cursor(new Gdk.Cursor.from_name("crosshair", null));
        set_child(da);

        // Mouse input on the drawing area
        var click = new Gtk.GestureClick();
        click.set_button(1);
        click.pressed.connect((n, x, y) => picker.on_press(geo.x + x, geo.y + y));
        click.released.connect((n, x, y) => picker.on_release(geo.x + x, geo.y + y));
        da.add_controller(click);

        var motion = new Gtk.EventControllerMotion();
        motion.motion.connect((x, y) => picker.on_motion(geo.x + x, geo.y + y));
        da.add_controller(motion);

        // Right-click or middle-click to cancel
        var cancel_click = new Gtk.GestureClick();
        cancel_click.set_button(0); // all buttons
        cancel_click.pressed.connect((n, x, y) => {
            uint btn = cancel_click.get_current_button();
            if (btn == 3 || btn == 2) picker.cancel();
        });
        da.add_controller(cancel_click);
    }

    public void queue_redraw() { da.queue_draw(); }

    private void on_draw(DrawingArea area, Cairo.Context cr, int width, int height) {
        // Semi-transparent dark overlay
        cr.set_source_rgba(0.0, 0.0, 0.0, 0.4);
        cr.paint();

        if (!picker.is_active) return;

        // Convert global selection rect to local coords
        double lx1 = picker.start_x < picker.end_x ? picker.start_x : picker.end_x;
        double ly1 = picker.start_y < picker.end_y ? picker.start_y : picker.end_y;
        double lx2 = picker.start_x > picker.end_x ? picker.start_x : picker.end_x;
        double ly2 = picker.start_y > picker.end_y ? picker.start_y : picker.end_y;

        lx1 -= geo.x; ly1 -= geo.y;
        lx2 -= geo.x; ly2 -= geo.y;

        // Clamp to this monitor's bounds
        lx1 = lx1.clamp(0, width);
        ly1 = ly1.clamp(0, height);
        lx2 = lx2.clamp(0, width);
        ly2 = ly2.clamp(0, height);

        double sw = lx2 - lx1;
        double sh = ly2 - ly1;
        if (sw <= 0 || sh <= 0) return;

        // Cut out the selected region (clear to show content below)
        cr.set_operator(Cairo.Operator.CLEAR);
        cr.rectangle(lx1, ly1, sw, sh);
        cr.fill();

        // Selection border
        cr.set_operator(Cairo.Operator.OVER);
        cr.set_source_rgba(1.0, 1.0, 1.0, 0.9);
        cr.set_line_width(1.5);
        cr.rectangle(lx1, ly1, sw, sh);
        cr.stroke();

        // Size label above selection
        string label = "%dx%d".printf(
            (int)(picker.end_x - picker.start_x).abs(),
            (int)(picker.end_y - picker.start_y).abs());
        cr.set_font_size(13.0);
        Cairo.TextExtents ext;
        cr.text_extents(label, out ext);
        double tx = lx1 + (sw - ext.width) / 2.0;
        double ty = (ly1 > 20) ? ly1 - 5.0 : ly2 + 15.0;

        // Label shadow
        cr.set_source_rgba(0.0, 0.0, 0.0, 0.8);
        cr.move_to(tx + 1, ty + 1);
        cr.show_text(label);
        // Label text
        cr.set_source_rgba(1.0, 1.0, 1.0, 1.0);
        cr.move_to(tx, ty);
        cr.show_text(label);
    }
}

void main(string[] args) {
    var picker = new RegionPicker();
    picker.run();
}
