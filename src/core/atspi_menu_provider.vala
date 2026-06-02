using Atspi;

namespace Singularity {

    /**
     * AtSpiMenuProvider - scans the AT-SPI accessibility tree of a running
     * application and builds a GLib.Menu from its menu bar.
     *
     * This is used as a last-resort fallback when neither GTK4 org.gtk.Menus
     * nor classic dbusmenu (com.canonical.AppMenu.Registrar) are available,
     * which is the case for apps like GIMP (GTK3, no GtkApplication menubar)
     * and any other app that exposes an accessibility tree but no DBus menu.
     */
    public class AtSpiMenuProvider : GLib.Object {

        private static bool atspi_ready = false;
        private static bool _scan_in_progress = false;
        private static GLib.Mutex _scan_mutex = GLib.Mutex ();

        /** Must be called once from the main thread before any scan. */

        public static void ensure_init() {
            if (!atspi_ready) {
                Atspi.init();
                atspi_ready = true;
            }
        }

        /**
         * Asynchronously scan the AT-SPI tree for `app_id`, build a GLib.Menu,
         * and add the required SimpleActions to `group`.
         * Calls `on_result` on the main thread when done (may pass null).
         */
        public static void build_menu_async(string app_id, SimpleActionGroup group,
                                             owned MenuReadyCallback on_result) {
            ensure_init();
            string captured_id = app_id.dup();
            var captured_group = group;
            owned MenuReadyCallback captured_cb = (owned) on_result;

            new Thread<void>("atspi-scan", () => {
                _scan_mutex.lock ();
                GLib.Menu? menu = null;
                try {
                    menu = build_menu_sync(captured_id, captured_group);
                } catch (Error e) {
                    warning("AT-SPI scan error: %s", e.message);
                }
                _scan_mutex.unlock ();
                var result = menu;
                GLib.Idle.add(() => {
                    captured_cb(result);
                    return Source.REMOVE;
                });
            });
        }

        public delegate void MenuReadyCallback(GLib.Menu? menu);

        // Internal synchronous scan (called from background thread)

        private static GLib.Menu? build_menu_sync(string app_id, SimpleActionGroup group)
                throws Error {
            var desktop = Atspi.get_desktop(0);
            if (desktop == null) return null;

            int n_apps = desktop.get_child_count();
            for (int i = 0; i < n_apps; i++) {
                Atspi.Accessible? app = null;
                try { app = desktop.get_child_at_index(i); } catch { continue; }
                if (app == null) continue;

                string? app_name = null;
                try { app_name = app.get_name(); } catch { continue; }
                if (app_name == null || app_name.length == 0) continue;
                if (!matches_app_id(app_name, app_id)) continue;

                int n_windows = 0;
                try { n_windows = app.get_child_count(); } catch { continue; }
                for (int j = 0; j < n_windows; j++) {
                    Atspi.Accessible? window = null;
                    try { window = app.get_child_at_index(j); } catch { continue; }
                    if (window == null) continue;

                    // Only inspect proper windows
                    Atspi.Role win_role = Atspi.Role.INVALID;
                    try {
                        win_role = window.get_role();
                        if (win_role != Atspi.Role.FRAME &&
                            win_role != Atspi.Role.DIALOG &&
                            win_role != Atspi.Role.WINDOW) continue;
                    } catch { continue; }

                    var menu_bar = find_menu_bar(window, 0);
                    if (menu_bar == null) continue;

                    int counter = 0;
                    var menu = build_from_bar(menu_bar, group, ref counter);
                    if (menu != null && menu.get_n_items() > 0) return menu;
                }
            }
            return null;
        }

        private static bool matches_app_id(string app_name, string app_id) {
            string ln = app_name.down().strip();
            string lid = app_id.down();
            if (ln == lid) return true;
            string[] parts = lid.split(".");
            if (parts.length > 0) {
                string last = parts[parts.length - 1];
                if (ln == last) return true;
                if (ln.has_prefix(last) || last.has_prefix(ln)) return true;
            }
            if (lid.contains(ln) && ln.length >= 3) return true;
            // "Google Chrome", remove spaces, "googlechrome" vs "com.google.chrome"
            string ln_nospace = ln.replace(" ", "");
            string lid_nospace = lid.replace(".", "");
            if (lid_nospace.contains(ln_nospace) && ln_nospace.length >= 4) return true;
            if (ln_nospace.length >= 4 && lid.contains(ln_nospace)) return true;
            return false;
        }

        private static Atspi.Accessible? find_menu_bar(Atspi.Accessible node, int depth) {
            if (depth > 6) return null;
            try {
                if (node.get_role() == Atspi.Role.MENU_BAR) return node;
                int n = node.get_child_count();
                for (int i = 0; i < n; i++) {
                    Atspi.Accessible? child = null;
                    try { child = node.get_child_at_index(i); } catch { continue; }
                    if (child == null) continue;
                    var found = find_menu_bar(child, depth + 1);
                    if (found != null) return found;
                }
            } catch (Error e) {
                debug("atspi: find_menu_bar failed: %s", e.message);
            }
            return null;
        }

        private static GLib.Menu? build_from_bar(Atspi.Accessible bar,
                                                   SimpleActionGroup group,
                                                   ref int counter) {
            var menu = new GLib.Menu();
            try {
                int n = bar.get_child_count();
                for (int i = 0; i < n; i++) {
                    Atspi.Accessible? child = null;
                    try { child = bar.get_child_at_index(i); } catch { continue; }
                    if (child == null) continue;
                    try {
                        if (child.get_role() != Atspi.Role.MENU) continue;
                        string name = child.get_name() ?? "";
                        if (name.length == 0) continue;
                        var submenu = build_submenu(child, group, ref counter);
                        if (submenu != null) menu.append_submenu(name, submenu);
                    } catch (Error e) {
                        debug("atspi: skipped a top-level menu: %s", e.message);
                    }
                }
            } catch (Error e) {
                debug("atspi: build_from_bar failed: %s", e.message);
            }
            return menu.get_n_items() > 0 ? menu : null;
        }

        private static GLib.Menu? build_submenu(Atspi.Accessible menu_node,
                                                  SimpleActionGroup group,
                                                  ref int counter) {
            var result = new GLib.Menu();
            var section = new GLib.Menu();
            try {
                int n = menu_node.get_child_count();
                for (int i = 0; i < n; i++) {
                    Atspi.Accessible? child = null;
                    try { child = menu_node.get_child_at_index(i); } catch { continue; }
                    if (child == null) continue;
                    try {
                        var role = child.get_role();
                        string name = child.get_name() ?? "";

                        if (role == Atspi.Role.SEPARATOR) {
                            if (section.get_n_items() > 0) {
                                result.append_section(null, section);
                                section = new GLib.Menu();
                            }
                            continue;
                        }
                        if (name.length == 0) continue;

                        if (role == Atspi.Role.MENU) {
                            var nested = build_submenu(child, group, ref counter);
                            if (nested != null) section.append_submenu(name, nested);
                        } else if (role == Atspi.Role.MENU_ITEM ||
                                   role == Atspi.Role.CHECK_MENU_ITEM ||
                                   role == Atspi.Role.RADIO_MENU_ITEM ||
                                   role == Atspi.Role.TEAROFF_MENU_ITEM) {
                            counter++;
                            string act_id = "atspi-%d".printf(counter);
                            var captured = child;
                            var act = new SimpleAction(act_id, null);
                            act.activate.connect(() => {
                                try {
                                    var ai = captured.get_action_iface();
                                    if (ai != null) ai.do_action(0);
                                } catch (Error e) {
                                    warning("AT-SPI activate: %s", e.message);
                                }
                            });
                            group.add_action(act);
                            section.append(name, "dbusmenu." + act_id);
                        }
                    } catch (Error e) {
                        debug("atspi: skipped a submenu item: %s", e.message);
                    }
                }
            } catch (Error e) {
                debug("atspi: build_submenu failed: %s", e.message);
            }
            if (section.get_n_items() > 0) result.append_section(null, section);
            return result.get_n_items() > 0 ? result : null;
        }
    }
}
