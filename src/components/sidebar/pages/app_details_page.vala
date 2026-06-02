using Gtk;
using Gee;
using Singularity.Widgets;

namespace Singularity.SidebarPages {

    // Represents one Flatpak permission toggle
    private class FlatpakPerm {
        public string label;
        public bool enabled;
        // CLI flags to enable/disable via `flatpak override --user`
        public string enable_flag;   // e.g. "--share=network"
        public string disable_flag;  // e.g. "--unshare=network"

        public FlatpakPerm(string label, bool enabled, string enable_flag, string disable_flag) {
            this.label = label;
            this.enabled = enabled;
            this.enable_flag = enable_flag;
            this.disable_flag = disable_flag;
        }
    }

    public class AppDetailsPage : SettingsPage {
        private SingularityApp app;
        private AppInfo app_info;

        public AppDetailsPage(SingularityApp app, AppInfo info) {
            base(info.get_name());
            this.app = app;
            this.app_info = info;
            back_clicked.connect(() => app.open_settings_page("apps"));
            build_info_section();
            build_permissions_section();
            build_settings_section();
        }

        // Returns the Flatpak application ID (e.g. "com.raggesilver.BlackBox")
        // extracted from the desktop file ID, or null if not a flatpak.

        private string? get_flatpak_id() {
            string cmd = app_info.get_commandline() ?? "";
            if (!cmd.contains("flatpak")) return null;
            string id = app_info.get_id() ?? "";
            if (id.has_suffix(".desktop")) id = id[0:id.length - 8];
            if (id.length == 0) return null;
            return id;
        }

        // Run a flatpak command, respecting the container environment.

        private async string? run_flatpak(string[] args, out int exit_status) {
            exit_status = -1;
            bool in_container = AppSystem.get_default().is_container;
            string[] argv;
            if (in_container) {
                argv = new string[1 + args.length];
                argv[0] = "host-spawn";
                for (int i = 0; i < args.length; i++) argv[i + 1] = args[i];
            } else {
                argv = args;
            }
            try {
                var subp = new Subprocess.newv(argv,
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                Bytes? out_bytes;
                yield subp.communicate_async(null, null, out out_bytes, null);
                exit_status = subp.get_exit_status();
                if (out_bytes == null) return "";
                uint8[] data = out_bytes.get_data();
                return ((string)data).dup();
            } catch (Error e) {
                warning("FlatpakPermissions: %s", e.message);
                return null;
            }
        }

        // Parse `flatpak info --show-permissions` ini-like output

        private ArrayList<FlatpakPerm> parse_flatpak_perms(string output) {
            // Build a map of section, key, raw value string
            string section = "";
            var keys = new HashTable<string, string>(str_hash, str_equal);
            foreach (string raw_line in output.split("\n")) {
                string line = raw_line.strip();
                if (line.has_prefix("[") && line.has_suffix("]")) {
                    section = line[1:line.length - 1];
                } else if (line.contains("=")) {
                    int eq = line.index_of("=");
                    string k = section + "/" + line[0:eq].strip();
                    string v = line[eq + 1:line.length].strip();
                    keys.set(k.down(), v);
                }
            }
            string shared    = keys.get("context/shared") ?? "";
            string sockets   = keys.get("context/sockets") ?? "";
            string devices   = keys.get("context/devices") ?? "";
            string features  = keys.get("context/features") ?? "";
            string filesys   = keys.get("context/filesystems") ?? "";

            var list = new ArrayList<FlatpakPerm>();

            // Shared
            list.add(new FlatpakPerm("Network",   shared.contains("network"),  "--share=network",   "--unshare=network"));
            list.add(new FlatpakPerm("IPC",       shared.contains("ipc"),      "--share=ipc",       "--unshare=ipc"));

            // Sockets
            list.add(new FlatpakPerm("X11",          sockets.contains("x11"),          "--socket=x11",          "--nosocket=x11"));
            list.add(new FlatpakPerm("Wayland",       sockets.contains("wayland"),       "--socket=wayland",       "--nosocket=wayland"));
            list.add(new FlatpakPerm("Fallback X11",  sockets.contains("fallback-x11"),  "--socket=fallback-x11",  "--nosocket=fallback-x11"));
            list.add(new FlatpakPerm("PulseAudio",    sockets.contains("pulseaudio"),    "--socket=pulseaudio",    "--nosocket=pulseaudio"));
            list.add(new FlatpakPerm("Session Bus",   sockets.contains("session-bus"),   "--socket=session-bus",   "--nosocket=session-bus"));
            list.add(new FlatpakPerm("System Bus",    sockets.contains("system-bus"),    "--socket=system-bus",    "--nosocket=system-bus"));
            list.add(new FlatpakPerm("SSH Auth",      sockets.contains("ssh-auth"),      "--socket=ssh-auth",      "--nosocket=ssh-auth"));
            list.add(new FlatpakPerm("Smart Card",    sockets.contains("pcsc"),          "--socket=pcsc",          "--nosocket=pcsc"));
            list.add(new FlatpakPerm("Printing (CUPS)", sockets.contains("cups"),        "--socket=cups",          "--nosocket=cups"));

            // Devices
            list.add(new FlatpakPerm("DRI (GPU)",     devices.contains("dri"),   "--device=dri",   "--nodevice=dri"));
            list.add(new FlatpakPerm("Input Devices", devices.contains("input"), "--device=input", "--nodevice=input"));
            list.add(new FlatpakPerm("KVM",           devices.contains("kvm"),   "--device=kvm",   "--nodevice=kvm"));
            list.add(new FlatpakPerm("Shared Memory", devices.contains("shm"),   "--device=shm",   "--nodevice=shm"));
            list.add(new FlatpakPerm("All Devices",   devices.contains("all"),   "--device=all",   "--nodevice=all"));

            // Features
            list.add(new FlatpakPerm("Development Tools",  features.contains("devel"),          "--allow=devel",          "--disallow=devel"));
            list.add(new FlatpakPerm("Multi-arch",         features.contains("multiarch"),       "--allow=multiarch",       "--disallow=multiarch"));
            list.add(new FlatpakPerm("Bluetooth",          features.contains("bluetooth"),       "--allow=bluetooth",       "--disallow=bluetooth"));
            list.add(new FlatpakPerm("CAN Bus",            features.contains("canbus"),          "--allow=canbus",          "--disallow=canbus"));
            list.add(new FlatpakPerm("Per-app /dev/shm",   features.contains("per-app-dev-shm"),"--allow=per-app-dev-shm",  "--disallow=per-app-dev-shm"));

            // Filesystems
            string[] fs_special = { "host", "host-os", "host-etc", "home" };
            string[] fs_xdg = {
                "xdg-desktop", "xdg-documents", "xdg-download", "xdg-music",
                "xdg-pictures", "xdg-public-share", "xdg-templates", "xdg-videos",
                "xdg-run", "xdg-config", "xdg-cache", "xdg-data"
            };
            string[] fs_labels = {
                "Host (Full)", "Host OS", "Host /etc", "Home",
                "Desktop", "Documents", "Downloads", "Music",
                "Pictures", "Public Share", "Templates", "Videos",
                "XDG Run", "Config", "Cache", "Data"
            };
            string[] all_fs = new string[fs_special.length + fs_xdg.length];
            string[] all_fs_labels = new string[fs_labels.length];
            for (int i = 0; i < fs_special.length; i++) { all_fs[i] = fs_special[i]; all_fs_labels[i] = fs_labels[i]; }
            for (int i = 0; i < fs_xdg.length; i++) { all_fs[fs_special.length + i] = fs_xdg[i]; all_fs_labels[fs_special.length + i] = fs_labels[fs_special.length + i]; }
            for (int i = 0; i < all_fs.length; i++) {
                // Check if the filesystem entry is present (with or without :ro/:rw/:create suffix)
                bool enabled = filesys_contains(filesys, all_fs[i]);
                list.add(new FlatpakPerm(all_fs_labels[i],
                    enabled,
                    "--filesystem=" + all_fs[i],
                    "--nofilesystem=" + all_fs[i]));
            }

            return list;
        }

        private bool filesys_contains(string filesys, string entry) {
            if (filesys.contains(entry + ";") || filesys.has_suffix(entry)) return true;
            if (filesys.contains(entry + ":ro") || filesys.contains(entry + ":rw") ||
                filesys.contains(entry + ":create")) return true;
            return false;
        }

        // Extract custom filesystem paths (not matching known patterns)

        private string[] parse_custom_filesystems(string filesys_str) {
            string[] known = {
                "host", "host-os", "host-etc", "home", "xdg-desktop", "xdg-documents",
                "xdg-download", "xdg-music", "xdg-pictures", "xdg-public-share",
                "xdg-templates", "xdg-videos", "xdg-run", "xdg-config", "xdg-cache", "xdg-data"
            };
            var custom = new GLib.List<string>();
            foreach (var entry in filesys_str.split(";")) {
                string e = entry.strip();
                if (e == "") continue;
                // Strip :ro/:rw/:create suffix for comparison
                string base_e = e;
                if (base_e.has_suffix(":ro")) base_e = base_e[0:base_e.length - 3];
                else if (base_e.has_suffix(":rw")) base_e = base_e[0:base_e.length - 3];
                else if (base_e.has_suffix(":create")) base_e = base_e[0:base_e.length - 7];
                bool is_known = false;
                foreach (var k in known) {
                    if (base_e == k) { is_known = true; break; }
                }
                if (!is_known) custom.append(e);
            }
            string[] result = new string[custom.length()];
            int idx = 0;
            foreach (var c in custom) result[idx++] = c;
            return result;
        }

        // Parse env vars from [Environment] section

        private string[] parse_env_vars(string output) {
            bool in_env = false;
            var vars = new GLib.List<string>();
            foreach (string raw_line in output.split("\n")) {
                string line = raw_line.strip();
                if (line.has_prefix("[") && line.has_suffix("]")) {
                    in_env = (line == "[Environment]");
                    continue;
                }
                if (in_env && line.contains("=")) {
                    vars.append(line);
                }
            }
            string[] result = new string[vars.length()];
            int idx = 0;
            foreach (var v in vars) result[idx++] = v;
            return result;
        }

        // Parse bus policies from a named section

        private string[] parse_bus_policy(string output, string section_name) {
            bool in_section = false;
            var policies = new GLib.List<string>();
            foreach (string raw_line in output.split("\n")) {
                string line = raw_line.strip();
                if (line.has_prefix("[") && line.has_suffix("]")) {
                    in_section = (line == "[" + section_name + "]");
                    continue;
                }
                if (in_section && line.contains("=")) {
                    policies.append(line);
                }
            }
            string[] result = new string[policies.length()];
            int idx = 0;
            foreach (var p in policies) result[idx++] = p;
            return result;
        }

        private void build_info_section() {
            var group = new PreferencesGroup();
            var row = new PreferencesRow();
            var box = new Box(Orientation.HORIZONTAL, 12);
            box.margin_top = 12;
            box.margin_bottom = 12;
            box.margin_start = 12;
            box.margin_end = 12;
            var icon = new Image.from_gicon(app_info.get_icon());
            icon.pixel_size = 64;
            box.append(icon);
            var vbox = new Box(Orientation.VERTICAL, 4);
            vbox.valign = Align.CENTER;
            var desc = new Label(app_info.get_description());
            desc.add_css_class("title");
            desc.halign = Align.START;
            desc.ellipsize = Pango.EllipsizeMode.END;
            desc.max_width_chars = 30;
            vbox.append(desc);
            var exec = new Label(app_info.get_executable());
            exec.add_css_class("subtitle");
            exec.halign = Align.START;
            vbox.append(exec);
            box.append(vbox);
            row.set_child(box);
            group.add_row(row);
            add_group(group);
        }

        private void build_permissions_section() {
            string? flatpak_id = get_flatpak_id();
            if (flatpak_id == null) return;

            var loading_group = new PreferencesGroup(_("Permissions"));
            var spinner_row = new PreferencesRow();
            var hbox = new Box(Orientation.HORIZONTAL, 8);
            hbox.halign = Align.CENTER;
            hbox.margin_top = 12;
            hbox.margin_bottom = 12;
            var spinner = new Spinner();
            spinner.spinning = true;
            hbox.append(spinner);
            var lbl = new Label(_("Loading permissions…"));
            lbl.add_css_class("dim-label");
            hbox.append(lbl);
            spinner_row.set_child(hbox);
            loading_group.add_row(spinner_row);
            add_group(loading_group);
            load_permissions_async.begin(loading_group, flatpak_id);
        }

        // Add a PreferencesGroup for a boolean permission section (Shared, Sockets, Devices, Features).

        private void add_perm_group(string title, string description, ArrayList<FlatpakPerm> perms, int from, int to, string flatpak_id) {
            int actual_to = int.min(to, perms.size);
            if (from >= actual_to) return;
            var group = new PreferencesGroup(title, description);
            for (int i = from; i < actual_to; i++) {
                var perm = perms[i];
                var row = new SwitchRow(perm.label, null, perm.enabled);
                string enable_flag = perm.enable_flag;
                string disable_flag = perm.disable_flag;
                string fid = flatpak_id;
                row.switch_btn.notify["active"].connect(() => {
                    apply_permission.begin(row.switch_btn, enable_flag, disable_flag, fid);
                });
                group.add_row(row);
            }
            add_group(group);
        }

        // Return human-readable access mode label for a named filesystem entry.

        private string? get_filesys_mode(string filesys_str, string entry) {
            foreach (string part in filesys_str.split(";")) {
                string e = part.strip();
                if (e == entry + ":ro") return "Read-only";
                if (e == entry + ":rw" || e == entry) return "Read-write";
                if (e == entry + ":create") return "Create";
            }
            return null;
        }

        // Build the Filesystems PreferencesGroup (named switches + custom path rows).
        private void build_filesystems_group(ArrayList<FlatpakPerm> perms, int from, int to,
                                              string filesys_raw, string flatpak_id) {
            int actual_to = int.min(to, perms.size);
            string[] custom_fs = parse_custom_filesystems(filesys_raw);
            if (from >= actual_to && custom_fs.length == 0) return;

            var group = new PreferencesGroup(_("Filesystems"), _("Access to host filesystem locations"));

            // Known/named filesystem entries as toggleable SwitchRows
            for (int i = from; i < actual_to; i++) {
                var perm = perms[i];
                // Derive the raw filesystem key from the enable flag (strip "--filesystem=")
                string fs_key = perm.enable_flag.replace("--filesystem=", "");
                string? mode = perm.enabled ? get_filesys_mode(filesys_raw, fs_key) : null;
                var row = new SwitchRow(perm.label, mode, perm.enabled);
                string enable_flag = perm.enable_flag;
                string disable_flag = perm.disable_flag;
                string fid = flatpak_id;
                row.switch_btn.notify["active"].connect(() => {
                    apply_permission.begin(row.switch_btn, enable_flag, disable_flag, fid);
                });
                group.add_row(row);
            }

            // Custom path entries as read-only ActionRows showing the full path
            foreach (string path in custom_fs) {
                string base_path = path;
                string? mode_label = null;
                if (base_path.has_suffix(":ro")) { base_path = base_path[0:base_path.length - 3]; mode_label = "Read-only"; }
                else if (base_path.has_suffix(":rw")) { base_path = base_path[0:base_path.length - 3]; mode_label = "Read-write"; }
                else if (base_path.has_suffix(":create")) { base_path = base_path[0:base_path.length - 7]; mode_label = "Create"; }
                else { mode_label = "Read-write"; }
                var row = new ActionRow(base_path, mode_label);
                row.activatable = false;
                group.add_row(row);
            }

            add_group(group);
        }

        // Build the Environment PreferencesGroup (key=value entries as ActionRows).

        private void build_env_group(string[] env_vars) {
            var group = new PreferencesGroup(_("Environment"), _("Environment variables set in the sandbox"));
            foreach (string env in env_vars) {
                int eq = env.index_of("=");
                string key = eq > 0 ? env[0:eq].strip() : env.strip();
                string val = eq > 0 ? env[eq + 1:env.length].strip() : "";
                var row = new ActionRow(key, val.length > 0 ? val : null);
                row.activatable = false;
                group.add_row(row);
            }
            add_group(group);
        }

        // Build a D-Bus policy PreferencesGroup (service=policy entries as ActionRows).

        private void build_bus_group(string title, string description, string[] policies) {
            var group = new PreferencesGroup(title, description);
            foreach (string policy in policies) {
                int eq = policy.index_of("=");
                string name = eq > 0 ? policy[0:eq].strip() : policy.strip();
                string access = eq > 0 ? policy[eq + 1:policy.length].strip() : "";
                var row = new ActionRow(name, access.length > 0 ? access : null);
                row.activatable = false;
                group.add_row(row);
            }
            add_group(group);
        }

        private async void load_permissions_async(PreferencesGroup loading_group, string flatpak_id) {
            int exit_status;
            string? output = yield run_flatpak({ "flatpak", "info", "--show-permissions", flatpak_id }, out exit_status);

            // Remove the loading placeholder group
            content_box.remove(loading_group);

            if (output == null || output.strip() == "") {
                var err_group = new PreferencesGroup(_("Permissions"));
                var err_row = new ActionRow(_("Could not read Flatpak permissions"));
                err_row.activatable = false;
                err_group.add_row(err_row);
                add_group(err_group);
                return;
            }

            // Parse the raw ini output
            var perms = parse_flatpak_perms(output);

            // Collect raw context values for extra sections
            string sec = "";
            var keys = new HashTable<string, string>(str_hash, str_equal);
            foreach (string raw_line in output.split("\n")) {
                string line = raw_line.strip();
                if (line.has_prefix("[") && line.has_suffix("]")) {
                    sec = line[1:line.length - 1];
                } else if (line.contains("=")) {
                    int eq = line.index_of("=");
                    string k = sec + "/" + line[0:eq].strip().down();
                    string v = line[eq + 1:line.length].strip();
                    keys.set(k, v);
                }
            }
            string filesys_raw = keys.get("context/filesystems") ?? "";

            // Per-section PreferencesGroups
            // Perm index ranges: 0–1 shared, 2–10 sockets, 11–15 devices, 16–20 features, 21+ filesystems
            add_perm_group("Shared",   "Network and IPC namespace sharing",   perms,  0,  2, flatpak_id);
            add_perm_group("Sockets",  "Well-known socket endpoints",         perms,  2, 11, flatpak_id);
            add_perm_group("Devices",  "Hardware device access",              perms, 11, 16, flatpak_id);
            add_perm_group("Features", "Optional kernel and runtime features", perms, 16, 21, flatpak_id);
            build_filesystems_group(perms, 21, perms.size, filesys_raw, flatpak_id);

            // Environment variables
            string[] env_vars = parse_env_vars(output);
            if (env_vars.length > 0) {
                build_env_group(env_vars);
            }

            // D-Bus policy
            string[] session_bus = parse_bus_policy(output, "Session Bus Policy");
            if (session_bus.length > 0) {
                build_bus_group("Session Bus", "Access D-Bus session bus services", session_bus);
            }
            string[] system_bus = parse_bus_policy(output, "System Bus Policy");
            if (system_bus.length > 0) {
                build_bus_group("System Bus", "Access D-Bus system bus services", system_bus);
            }
        }

        private async void apply_permission(Switch sw, string enable_flag, string disable_flag, string flatpak_id) {
            bool desired = sw.active;
            sw.sensitive = false;
            string flag = desired ? enable_flag : disable_flag;
            int exit_code;
            yield run_flatpak({ "flatpak", "override", "--user", flag, flatpak_id }, out exit_code);
            sw.sensitive = true;
            if (exit_code != 0) {
                // Revert to previous state without re-triggering the notify signal
                GLib.SignalHandler.block_matched(sw, GLib.SignalMatchType.DATA, 0, 0, null, null, sw);
                sw.active = !desired;
                GLib.SignalHandler.unblock_matched(sw, GLib.SignalMatchType.DATA, 0, 0, null, null, sw);
            }
        }

        private void build_settings_section() {
            var group = new PreferencesGroup(_("App Settings"));
            var loading_row = new PreferencesRow();
            var loading = new Label(_("Loading settings..."));
            loading.add_css_class("dim-label");
            loading.margin_top = 12;
            loading.margin_bottom = 12;
            loading_row.set_child(loading);
            group.add_row(loading_row);
            add_group(group);
            load_settings.begin(group, loading_row);
        }

        private async void load_settings(PreferencesGroup group, PreferencesRow loading_row) {
            string app_id = app_info.get_id();
            message("AppDetailsPage: Loading settings for app_id='%s'", app_id);
            var descriptor = Singularity.Core.AppSettingsLoader.load_for_app(app_id);
            if (descriptor == null) {
                group.remove_row(loading_row);
                var row = new PreferencesRow();
                var lbl = new Label(_("No settings available"));
                lbl.add_css_class("dim-label");
                lbl.margin_top = 12;
                lbl.margin_bottom = 12;
                row.set_child(lbl);
                group.add_row(row);
                return;
            }
            group.remove_row(loading_row);
            GLib.Settings settings = null;
            try {
                var source = SettingsSchemaSource.get_default();
                var schema = source.lookup(descriptor.schema_id, true);
                if (schema == null) {
                    warning("Schema %s not found", descriptor.schema_id);
                    var row = new PreferencesRow();
                    var err = new Label(_("Settings schema not found"));
                    err.add_css_class("error-label");
                    err.margin_top = 12;
                    err.margin_bottom = 12;
                    row.set_child(err);
                    group.add_row(row);
                    return;
                }
                settings = new GLib.Settings(descriptor.schema_id);
            } catch (Error e) {
                warning("Failed to load settings schema: %s", e.message);
                return;
            }
            foreach (var item in descriptor.items) {
                if (item.setting_type == "boolean") {
                    var row = new SwitchRow(item.label, null, settings.get_boolean(item.key));
                    settings.bind(item.key, row.switch_btn, "active", SettingsBindFlags.DEFAULT);
                    group.add_row(row);
                } else if (item.setting_type == "int") {
                    var row = new ActionRow(item.label);
                    if (item.widget == "spin") {
                        var adj = new Adjustment(settings.get_int(item.key), item.min, item.max, 1, 10, 0);
                        var spin = new SpinButton(adj, 1, 0);
                        spin.valign = Align.CENTER;
                        settings.bind(item.key, spin, "value", SettingsBindFlags.DEFAULT);
                        row.add_suffix(spin);
                    } else {
                        var entry = new Entry();
                        entry.text = settings.get_int(item.key).to_string();
                        entry.valign = Align.CENTER;
                        entry.width_chars = 5;
                        entry.activate.connect(() => {
                            settings.set_int(item.key, int.parse(entry.text));
                        });
                        row.add_suffix(entry);
                    }
                    group.add_row(row);
                } else if (item.setting_type == "string") {
                    if (item.widget == "color-scheme-selector") {
                        Gee.ArrayList<Singularity.Widgets.ColorTheme> themes = null;
                        if (item.theme_set == "terminal" || item.theme_set == "leafs") {
                            themes = Singularity.Core.TerminalThemes.get_all();
                        } else if (item.theme_set == "edit" || item.theme_set == "write") {
                            themes = Singularity.Core.EditThemes.get_all();
                        } else {
                            // Fallback: try all providers and use the one that
                            // contains the current value, or the first non-empty
                            string current = settings.get_string(item.key);
                            var terminal_themes = Singularity.Core.TerminalThemes.get_all();
                            var edit_themes = Singularity.Core.EditThemes.get_all();
                            if (current != null && current != "") {
                                foreach (var t in terminal_themes)
                                    if (t.id == current) { themes = terminal_themes; break; }
                                if (themes == null) {
                                    foreach (var t in edit_themes)
                                        if (t.id == current) { themes = edit_themes; break; }
                                }
                            }
                            if (themes == null) themes = terminal_themes;
                        }
                        if (themes != null) {
                            var current = settings.get_string(item.key);
                            var row = new ColorSchemeRow(item.label, themes, current);
                            row.scheme_selected.connect((id) => {
                                settings.set_string(item.key, id);
                            });
                            settings.changed[item.key].connect(() => {
                                row.current_scheme = settings.get_string(item.key);
                            });
                            group.add_row(row);
                        }
                    } else if (item.widget == "combo") {
                        var current = settings.get_string(item.key);
                        var row = new SelectionRow.with_options(item.label, item.options, current);
                        row.selected.connect((id) => {
                            settings.set_string(item.key, id);
                        });
                        settings.changed[item.key].connect(() => {
                            row.current_value = settings.get_string(item.key);
                        });
                        group.add_row(row);
                    }
                }
            }
        }
    }
}
