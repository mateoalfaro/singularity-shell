using Gtk;
using Gdk;
using Cairo;

namespace Singularity.Shell {

    public class MonitorPreview : DrawingArea {
        private DisplayManager display_manager;
        private DisplayManager.Monitor? dragging_monitor = null;
        private double drag_start_x;
        private double drag_start_y;
        private int monitor_start_x;
        private int monitor_start_y;
        private double view_scale = 0.1;
        private int offset_x = 0;
        private int offset_y = 0;
        private bool _is_dragging = false;
        public string shell_monitor_name { get; set; default = ""; }
        public signal void layout_changed();
        public signal void shell_monitor_changed(string connector_name);

        public MonitorPreview() {
            display_manager = DisplayManager.get_default();
            display_manager.monitors_changed.connect(queue_draw);
            set_draw_func(draw_func);
            var gesture_drag = new Gtk.GestureDrag();
            gesture_drag.drag_begin.connect(on_drag_begin);
            gesture_drag.drag_update.connect(on_drag_update);
            gesture_drag.drag_end.connect(on_drag_end);
            add_controller(gesture_drag);
            var gesture_click = new Gtk.GestureClick();
            gesture_click.button = 1;
            gesture_click.pressed.connect(on_click_pressed);
            add_controller(gesture_click);
            set_size_request(-1, 200);
            add_css_class("monitor-preview");
        }

        private void calculate_view_transform(int width, int height) {
            int min_x = int.MAX;
            int min_y = int.MAX;
            int max_x = int.MIN;
            int max_y = int.MIN;
            foreach (var m in display_manager.get_monitors()) {
                if (!m.enabled) continue;
                if (m.x < min_x) min_x = m.x;
                if (m.y < min_y) min_y = m.y;
                int w = m.current_mode != null ? m.current_mode.width : 1920;
                int h = m.current_mode != null ? m.current_mode.height : 1080;
                if (m.transform == 1 || m.transform == 3 || m.transform == 5 || m.transform == 7) {
                    int temp = w; w = h; h = temp;
                }
                if (m.x + w > max_x) max_x = m.x + w;
                if (m.y + h > max_y) max_y = m.y + h;
            }
            if (min_x == int.MAX) {
                return;
            }
            int total_w = max_x - min_x;
            int total_h = max_y - min_y;
            total_w += 1000;
            total_h += 1000;
            double scale_x = (double)width / total_w;
            double scale_y = (double)height / total_h;
            view_scale = double.min(scale_x, scale_y);
            offset_x = (int)((width - (total_w - 1000) * view_scale) / 2) - (int)(min_x * view_scale);
            offset_y = (int)((height - (total_h - 1000) * view_scale) / 2) - (int)(min_y * view_scale);
        }

        private void draw_func(DrawingArea area, Context cr, int width, int height) {
            calculate_view_transform(width, height);
            calculate_view_transform(width, height);
            int index = 1;
            foreach (var m in display_manager.get_monitors()) {
                if (!m.enabled) continue;
                int w = m.current_mode != null ? m.current_mode.width : 1920;
                int h = m.current_mode != null ? m.current_mode.height : 1080;
                if (m.transform == 1 || m.transform == 3 || m.transform == 5 || m.transform == 7) {
                    int temp = w; w = h; h = temp;
                }
                double x = m.x * view_scale + offset_x;
                double y = m.y * view_scale + offset_y;
                double dw = w * view_scale;
                double dh = h * view_scale;
                // Monitor body
                rounded_rect(cr, x, y, dw, dh, 4.0);
                cr.set_source_rgba(0.18, 0.18, 0.18, 1.0);
                cr.fill_preserve();
                if (m == dragging_monitor) {
                    cr.set_source_rgba(0.3, 0.6, 1.0, 1.0);
                    cr.set_line_width(2.0);
                } else {
                    cr.set_source_rgba(0.38, 0.38, 0.38, 1.0);
                    cr.set_line_width(1.0);
                }
                cr.stroke();

                bool is_shell = (m.name == shell_monitor_name && shell_monitor_name != "");
                double bar_alpha = is_shell ? 0.70 : 0.38;

                // Topbar skeleton
                double topbar_h = double.max(4.0, dh * 0.06);
                rounded_rect(cr, x + 2, y + 2, dw - 4, topbar_h, 2.0);
                cr.set_source_rgba(0.55, 0.55, 0.55, bar_alpha);
                cr.fill();

                // Tiny dots in topbar (clock / icons hint)
                double dot_y = y + 2 + topbar_h / 2;
                double dot_r = double.max(1.0, topbar_h * 0.18);
                for (int d = 0; d < 3; d++) {
                    cr.arc(x + dw - 6 - d * (dot_r * 2 + 2), dot_y, dot_r, 0, 2 * Math.PI);
                    cr.set_source_rgba(0.75, 0.75, 0.75, bar_alpha);
                    cr.fill();
                }

                // Dock skeleton
                double dock_h = double.max(6.0, dh * 0.10);
                double dock_w = dw * 0.55;
                double dock_x = x + (dw - dock_w) / 2;
                double dock_y = y + dh - dock_h - 3;
                rounded_rect(cr, dock_x, dock_y, dock_w, dock_h, 3.0);
                cr.set_source_rgba(0.50, 0.50, 0.50, bar_alpha);
                cr.fill();

                // Tiny icon dots in dock
                int n_icons = (int)(dock_w / (dock_h * 1.4));
                if (n_icons > 8) n_icons = 8;
                double icon_r = double.max(1.5, dock_h * 0.22);
                double icon_spacing = dock_w / (n_icons + 1);
                for (int d = 0; d < n_icons; d++) {
                    cr.arc(dock_x + icon_spacing * (d + 1), dock_y + dock_h / 2, icon_r, 0, 2 * Math.PI);
                    cr.set_source_rgba(0.80, 0.80, 0.80, bar_alpha);
                    cr.fill();
                }

                // Monitor number badge
                cr.select_font_face("Inter", FontSlant.NORMAL, FontWeight.BOLD);
                cr.set_font_size(20.0);
                string num = index.to_string();
                TextExtents extents;
                cr.text_extents(num, out extents);
                double badge_cx = x + dw / 2;
                double badge_cy = y + dh / 2;
                cr.arc(badge_cx, badge_cy, 16, 0, 2 * Math.PI);
                cr.set_source_rgba(is_shell ? 0.2 : 0.85, is_shell ? 0.55 : 0.85, is_shell ? 1.0 : 0.85, 1.0);
                cr.fill();
                cr.set_source_rgba(is_shell ? 1.0 : 0.1, is_shell ? 1.0 : 0.1, is_shell ? 1.0 : 0.1, 1.0);
                cr.move_to(badge_cx - extents.width / 2 - extents.x_bearing,
                           badge_cy - extents.height / 2 - extents.y_bearing);
                cr.show_text(num);

                index++;
            }
        }

        private void on_drag_begin(Gtk.GestureDrag gesture, double start_x, double start_y) {
            _is_dragging = false;
            dragging_monitor = null;
            unowned var monitors = display_manager.get_monitors();
            for (int i = (int)monitors.length() - 1; i >= 0; i--) {
                var m = monitors.nth_data(i);
                if (!m.enabled) continue;
                int w = m.current_mode != null ? m.current_mode.width : 1920;
                int h = m.current_mode != null ? m.current_mode.height : 1080;
                if (m.transform % 2 != 0) { int t = w; w = h; h = t; }
                double mx = m.x * view_scale + offset_x;
                double my = m.y * view_scale + offset_y;
                double mw = w * view_scale;
                double mh = h * view_scale;
                if (start_x >= mx && start_x <= mx + mw && start_y >= my && start_y <= my + mh) {
                    dragging_monitor = m;
                    drag_start_x = start_x;
                    drag_start_y = start_y;
                    monitor_start_x = m.x;
                    monitor_start_y = m.y;
                    queue_draw();
                    break;
                }
            }
        }

        private void on_drag_update(Gtk.GestureDrag gesture, double offset_x, double offset_y) {
            if (dragging_monitor != null) {
                if ((offset_x * offset_x + offset_y * offset_y) > 25.0) {
                    _is_dragging = true;
                }
                int dx = (int)(offset_x / view_scale);
                int dy = (int)(offset_y / view_scale);
                dragging_monitor.x = monitor_start_x + dx;
                dragging_monitor.y = monitor_start_y + dy;
                queue_draw();
            }
        }

        private void on_drag_end(Gtk.GestureDrag gesture, double offset_x, double offset_y) {
            if (dragging_monitor != null && _is_dragging) {
                snap_to_grid();
                layout_changed();
            }
            dragging_monitor = null;
            _is_dragging = false;
            queue_draw();
        }

        private void on_click_pressed(Gtk.GestureClick gesture, int n_press, double click_x, double click_y) {
            if (_is_dragging) return;
            unowned var monitors = display_manager.get_monitors();
            for (int i = (int)monitors.length() - 1; i >= 0; i--) {
                var m = monitors.nth_data(i);
                if (!m.enabled) continue;
                int w = m.current_mode != null ? m.current_mode.width : 1920;
                int h = m.current_mode != null ? m.current_mode.height : 1080;
                if (m.transform % 2 != 0) { int t = w; w = h; h = t; }
                double mx = m.x * view_scale + offset_x;
                double my = m.y * view_scale + offset_y;
                double mw = w * view_scale;
                double mh = h * view_scale;
                if (click_x >= mx && click_x <= mx + mw && click_y >= my && click_y <= my + mh) {
                    shell_monitor_name = m.name;
                    shell_monitor_changed(m.name);
                    queue_draw();
                    break;
                }
            }
        }

        private void snap_to_grid() {
            // Collect enabled monitors into array
            DisplayManager.Monitor[] enabled = {};
            foreach (var m in display_manager.get_monitors()) {
                if (m.enabled) enabled += m;
            }
            if (enabled.length == 0) return;
            // Sort array by current dragged x position (bubble sort - small array)
            for (int i = 0; i < enabled.length - 1; i++) {
                for (int j = 0; j < enabled.length - 1 - i; j++) {
                    if (enabled[j].x > enabled[j + 1].x) {
                        var tmp = enabled[j];
                        enabled[j] = enabled[j + 1];
                        enabled[j + 1] = tmp;
                    }
                }
            }
            // Pack monitors left-to-right with no gaps, using each monitor's own width
            int cursor = 0;
            foreach (var m in enabled) {
                int w = m.current_mode != null ? m.current_mode.width : 1920;
                m.x = cursor;
                m.y = 0;
                cursor += w;
            }
        }

        private void rounded_rect(Cairo.Context cr, double x, double y, double w, double h, double r) {
            cr.new_sub_path();
            cr.arc(x + r,     y + r,     r, Math.PI,       1.5 * Math.PI);
            cr.arc(x + w - r, y + r,     r, 1.5 * Math.PI, 2.0 * Math.PI);
            cr.arc(x + w - r, y + h - r, r, 0,             0.5 * Math.PI);
            cr.arc(x + r,     y + h - r, r, 0.5 * Math.PI, Math.PI);
            cr.close_path();
        }

    }
}
