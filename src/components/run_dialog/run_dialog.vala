using Gtk;

namespace Singularity {

    public class RunDialog : Singularity.Shell.ShellDialog {
        private Entry   entry;
        private Label   error_label;
        private Label   hint;
        private Revealer suggestions_revealer;
        private ListBox suggestions_list;
        private Singularity.Animation.TimedAnimation? dialog_animation;
        private GLib.Settings _desktop_settings = new GLib.Settings("dev.sinty.desktop");

        // Developer-only run commands (nested session, restart compositor) and
        // their hints are only available when developer mode is enabled.
        private bool dev_mode() {
            return _desktop_settings.get_boolean("developer-mode");
        }

        private void update_hint() {
            hint.label = dev_mode()
                ? "r = restart shell, c = reload compositor config, n = nested test, Up/Down = history, ESC = close"
                : "r = restart shell, Up/Down = history, ESC = close";
        }

        // History
        private string[] _history    = {};
        private int      _history_pos = -1;

        // App suggestions, backed by the system app registry.
        private class AppSuggestion {
            public AppInfo info;
            public string name;
            public string name_lc;
            public string exec_lc;
            public AppSuggestion(AppInfo info) {
                this.info = info;
                this.name = info.get_display_name();
                this.name_lc = name.down();
                string? exe = info.get_executable();
                this.exec_lc = (exe != null) ? exe.down() : "";
            }
        }
        private AppSuggestion[] _apps = {};

        public RunDialog(Gtk.Application app) {
            Object(
                application: app,
                anchor_top: true,
                anchor_bottom: true,
                anchor_left: true,
                anchor_right: true
            );
            add_css_class("run-dialog");

            entry = new Entry();
            entry.placeholder_text = _("Search apps or run a command…");
            entry.primary_icon_name = "system-search-symbolic";
            entry.primary_icon_activatable = false;
            entry.primary_icon_sensitive = false;
            entry.width_request = 420;
            entry.add_css_class("run-entry");
            entry.activate.connect(on_activate);
            entry.changed.connect(on_text_changed);
            content_box.append(entry);

            // Error feedback label
            error_label = new Label("");
            error_label.add_css_class("run-error");
            error_label.halign = Align.START;
            error_label.visible = false;
            error_label.wrap = true;
            error_label.xalign = 0;
            content_box.append(error_label);

            // App suggestions list
            suggestions_revealer = new Revealer();
            suggestions_revealer.transition_type = RevealerTransitionType.SLIDE_DOWN;
            suggestions_revealer.transition_duration = 120;
            suggestions_list = new ListBox();
            suggestions_list.add_css_class("run-suggestions");
            suggestions_list.selection_mode = SelectionMode.SINGLE;
            suggestions_list.row_activated.connect(on_suggestion_activated);
            suggestions_revealer.child = suggestions_list;
            content_box.append(suggestions_revealer);

            // Hint bar
            var hint_box = new Box(Orientation.HORIZONTAL, 0);
            hint_box.add_css_class("run-hint");
            hint = new Label("");
            update_hint();
            hint.add_css_class("dim-label");
            hint.add_css_class("caption");
            hint.halign = Align.CENTER;
            hint.hexpand = true;
            // Keep the text off the rounded edges.
            hint.margin_start = 14;
            hint.margin_end = 14;
            hint.wrap = true;
            hint.justify = Justification.CENTER;
            hint_box.append(hint);
            content_box.append(hint_box);

            // Keyboard controller for history navigation
            var key_ctrl = new EventControllerKey();
            key_ctrl.key_pressed.connect(on_key_pressed);
            entry.add_controller(key_ctrl);

            hide();
        }

        // History

        private void load_history() {
            string path = GLib.Path.build_filename(
                GLib.Environment.get_user_data_dir(), "singularity", "run_history");
            try {
                string contents;
                GLib.FileUtils.get_contents(path, out contents);
                _history = contents.strip().split("\n");
            } catch { _history = {}; }
        }

        private void save_to_history(string cmd) {
            if (cmd.strip() == "") return;
            string[] new_history = { cmd.strip() };
            foreach (string h in _history) {
                if (h.strip() != "" && h.strip() != cmd.strip())
                    new_history += h.strip();
                if (new_history.length >= 50) break;
            }
            _history = new_history;
            string path = GLib.Path.build_filename(
                GLib.Environment.get_user_data_dir(), "singularity", "run_history");
            try {
                GLib.DirUtils.create_with_parents(GLib.Path.get_dirname(path), 0755);
                GLib.FileUtils.set_contents(path, string.joinv("\n", _history));
            } catch {}
        }

        // App suggestions

        private void load_apps() {
            // Use the same list AppSystem already scanned (covers /opt and every
            // configured app dir, refreshed on changes) so the run dialog finds
            // exactly what the launcher does, rather than re-deriving it.
            _apps = {};
            var app_system = AppSystem.get_default();
            unowned List<AppInfo> apps = app_system.get_all_apps();
            if (apps == null || apps.length() == 0) {
                app_system.scan_apps();
                apps = app_system.get_all_apps();
            }
            foreach (AppInfo info in apps) {
                if (!info.should_show()) continue;
                _apps += new AppSuggestion(info);
            }
        }

        private void on_text_changed() {
            string query = entry.text.strip();
            error_label.visible = false;

            // Lens while empty (search), run gear once a command is typed.
            entry.primary_icon_name = (query == "")
                ? "system-search-symbolic"
                : "system-run-symbolic";

            // Clear suggestions list
            while (suggestions_list.get_first_child() != null)
                suggestions_list.remove(suggestions_list.get_first_child());

            if (query.length < 2) {
                suggestions_revealer.reveal_child = false;
                return;
            }

            string q = query.down();
            int count = 0;
            foreach (var a in _apps) {
                if (!a.name_lc.contains(q) && !a.exec_lc.contains(q)) continue;
                var row = new ListBoxRow();
                var row_box = new Box(Orientation.HORIZONTAL, 8);
                row_box.margin_start = 8; row_box.margin_end = 8;
                row_box.margin_top = 6;   row_box.margin_bottom = 6;
                var img = new Image();
                img.pixel_size = 20;
                var gicon = a.info.get_icon();
                if (gicon != null) img.set_from_gicon(gicon);
                else img.icon_name = "application-x-executable";
                row_box.append(img);
                var lbl = new Label(a.name);
                lbl.halign = Align.START;
                lbl.hexpand = true;
                row_box.append(lbl);
                row.set_child(row_box);
                row.set_data<AppInfo>("info", a.info);
                suggestions_list.append(row);
                if (++count >= 6) break;
            }

            suggestions_revealer.reveal_child = count > 0;
        }

        private void on_suggestion_activated(ListBoxRow row) {
            AppInfo? info = row.get_data<AppInfo>("info");
            suggestions_revealer.reveal_child = false;
            if (info == null) return;
            // Launch the app the standard way (handles field codes, terminal
            // apps, D-Bus activation and startup notification), not the terminal.
            try {
                info.launch(null, null);
                save_to_history(info.get_display_name());
                close_dialog();
            } catch (Error e) {
                error_label.label = _("Error: %s").printf(e.message);
                error_label.visible = true;
            }
        }

        // Keyboard navigation

        private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state) {
            if (keyval == Gdk.Key.Up) {
                if (_history.length == 0) return true;
                _history_pos = int.min(_history_pos + 1, (int)_history.length - 1);
                entry.text = _history[_history_pos];
                entry.set_position(-1);
                return true;
            }
            if (keyval == Gdk.Key.Down) {
                if (_history_pos <= 0) {
                    _history_pos = -1;
                    entry.text = "";
                } else {
                    _history_pos--;
                    entry.text = _history[_history_pos];
                    entry.set_position(-1);
                }
                return true;
            }
            if (keyval == Gdk.Key.Escape) {
                close_dialog();
                return true;
            }
            return false;
        }

        // Execute

        private void on_activate() {
            string cmd = entry.text.strip();
            if (cmd == "") return;

            error_label.visible = false;

            if (cmd == "r") {
                close_dialog();
                Posix.kill(Posix.getpid(), Posix.Signal.USR1);
                return;
            }
            if (cmd == "c" && dev_mode()) {
                close_dialog();
                Singularity.Compositor.LabwcBackend.get_default().reconfigure();
                GLib.Timeout.add(300, () => {
                    Posix.kill(Posix.getpid(), Posix.Signal.USR1);
                    return GLib.Source.REMOVE;
                });
                return;
            }
            if (cmd == "n" && dev_mode()) {
                // Nested test session: launch a fresh labwc + shell as a
                // WINDOW inside the current session, on a private DBus bus so
                // the nested shell's dev.sinty.* names don't clash with us.
                // Lets you test compositor/shell changes without logging out
                // (run `make deploy-host` first to refresh /opt/local).
                close_dialog();
                launch_nested_session();
                return;
            }
            // A typed command runs in the user's default terminal. Keep the
            // terminal open after it exits by dropping into a login shell.
            string inner = cmd + "; exec \"${SHELL:-bash}\"";
            string wrapped = "sh -lc " + GLib.Shell.quote(inner);
            try {
                // GLib resolves the system default terminal for us (respects a
                // user-configured choice); NEEDS_TERMINAL runs the command in it.
                var info = AppInfo.create_from_commandline(
                    wrapped, null, AppInfoCreateFlags.NEEDS_TERMINAL);
                info.launch(null, null);
                save_to_history(cmd);
                close_dialog();
            } catch (Error e) {
                // GLib found no terminal it knows: fall back to the shell's own
                // resolver (which prefers singularity-leafs).
                try {
                    SystemMonitor.get_default().shortcuts.spawn_terminal_with_command(wrapped);
                    save_to_history(cmd);
                    close_dialog();
                } catch (Error e2) {
                    error_label.label = _("Error: %s").printf(e2.message);
                    error_label.visible = true;
                }
            }
        }

        // Launch a nested Singularity (labwc + shell) as a window on a
        // private DBus session bus.
        private void launch_nested_session() {
            // Derive the install prefix from our own binary instead of hardcoding
            // it, so the nested session works whatever the prefix (/opt, /usr, ...).
            string prefix = "/opt/local";
            try {
                string exe = GLib.FileUtils.read_link("/proc/self/exe");
                prefix = GLib.Path.get_dirname(GLib.Path.get_dirname(exe));
            } catch (Error e) { }
            string script = ("""
set -e
export LD_LIBRARY_PATH=%s/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export GSETTINGS_SCHEMA_DIR=%s/share/glib-2.0/schemas
export PATH=%s/bin:$PATH
export GDK_BACKEND=wayland
export GSK_RENDERER=gl
export XDG_CURRENT_DESKTOP=Singularity
S=$(mktemp /tmp/sing-nested.XXXXXX.sh)
cat > "$S" <<'INNER'
#!/bin/bash
%s/bin/singularity-desktop &
sleep 1
( command -v gtk4-demo >/dev/null && gtk4-demo ) &
( command -v gnome-text-editor >/dev/null && gnome-text-editor ) &
INNER
chmod +x "$S"
exec dbus-run-session -- %s/bin/labwc -s "$S"
""").printf(prefix, prefix, prefix, prefix, prefix);
            try {
                Process.spawn_async(null,
                    { "/bin/bash", "-c", script, null },
                    null, SpawnFlags.SEARCH_PATH, null, null);
            } catch (Error e) {
                error_label.label = _("Nested launch failed: %s").printf(e.message);
                error_label.visible = true;
            }
        }

        // Animation

        public override void open_dialog() {
            update_hint();
            load_apps();
            load_history();
            _history_pos = -1;
            opacity = 0;
            if (dialog_animation != null) dialog_animation.skip();
            dialog_animation = new Singularity.Animation.TimedAnimation(
                this, 0, 1, 180,
                Singularity.Animation.TimedAnimation.Easing.EASE_OUT_CUBIC
            );
            dialog_animation.tick.connect(() => { opacity = dialog_animation.value; });
            dialog_animation.play();
            present();
        }

        public override void close_dialog() {
            suggestions_revealer.reveal_child = false;
            error_label.visible = false;
            if (dialog_animation != null) dialog_animation.skip();
            dialog_animation = new Singularity.Animation.TimedAnimation(
                this, 1, 0, 130,
                Singularity.Animation.TimedAnimation.Easing.EASE_IN_CUBIC
            );
            dialog_animation.tick.connect(() => { opacity = dialog_animation.value; });
            dialog_animation.done.connect(() => { hide(); });
            dialog_animation.play();
        }

        public void toggle() {
            if (visible) {
                close_dialog();
            } else {
                entry.text = "";
                open_dialog();
                entry.grab_focus();
            }
        }
    }
}
