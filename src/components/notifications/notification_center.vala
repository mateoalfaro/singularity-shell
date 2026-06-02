using Gtk;
using Singularity;

namespace Singularity {

    public class NotificationCenter : Box {
        private Box list_box;
        private Label empty_label;

        public NotificationCenter() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class("notification-center");

            // Notification List
            list_box = new Box(Orientation.VERTICAL, 10);
            list_box.margin_start = 16;
            list_box.margin_end = 16;
            list_box.margin_bottom = 20;
            list_box.margin_top = 10;
            append(list_box);

            // Empty State
            empty_label = new Label(_("No new notifications"));
            empty_label.add_css_class("dim-label");
            empty_label.vexpand = true;
            empty_label.valign = Align.CENTER;
            empty_label.halign = Align.CENTER;
            empty_label.margin_bottom = 30;
            append(empty_label);

            var manager = SystemMonitor.get_default().notifications;
            manager.history_changed.connect(update_list);
            update_list();
        }

        private void update_list() {
            var child = list_box.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                list_box.remove(child);
                child = next;
            }

            unowned var history = SystemMonitor.get_default().notifications.get_history();

            if (history.length() == 0) {
                list_box.visible = false;
                empty_label.visible = true;
                return;
            }

            list_box.visible = true;
            empty_label.visible = false;

            // Group notifications by app_name, preserving insertion order
            var seen_apps = new GLib.List<string>();
            foreach (var notif in history) {
                bool found = false;
                foreach (var name in seen_apps) {
                    if (name == notif.app_name) { found = true; break; }
                }
                if (!found) seen_apps.append(notif.app_name);
            }

            foreach (var app_name in seen_apps) {
                var group = new GLib.List<unowned Notification>();
                foreach (var notif in history) {
                    if (notif.app_name == app_name) group.append(notif);
                }
                if (group.length() == 1) {
                    list_box.append(new NotificationItem(group.data));
                } else {
                    list_box.append(new NotificationGroup(app_name, group));
                }
            }
        }
    }

    public class NotificationGroup : Box {
        private bool expanded = false;
        private Revealer revealer;
        private Image expand_icon;

        public NotificationGroup(string app_name, GLib.List<unowned Notification> notifications) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class("notification-group");

            // Header row (always visible): icon + [name+preview] + count badge + clear + expand toggle
            var header = new Box(Orientation.HORIZONTAL, 8);
            header.add_css_class("notification-group-header");
            header.margin_top = 10;
            header.margin_bottom = 10;
            header.margin_start = 12;
            header.margin_end = 10;

            var icon_img = new Image();
            icon_img.pixel_size = 16;
            load_notification_icon(icon_img, notifications.data.icon, app_name);
            header.append(icon_img);

            // Name + last notification preview in a VBox
            var name_box = new Box(Orientation.VERTICAL, 1);
            name_box.hexpand = true;
            name_box.halign = Align.FILL;
            name_box.valign = Align.CENTER;

            var app_label = new Label(app_name);
            app_label.add_css_class("notification-group-appname");
            app_label.halign = Align.START;
            app_label.ellipsize = Pango.EllipsizeMode.END;
            name_box.append(app_label);

            unowned var last_notif = notifications.last().data;
            string preview_text = last_notif.summary != "" ? last_notif.summary : last_notif.body;
            if (preview_text != "") {
                var preview_label = new Label(preview_text);
                preview_label.add_css_class("notification-group-preview");
                preview_label.halign = Align.START;
                preview_label.ellipsize = Pango.EllipsizeMode.END;
                preview_label.max_width_chars = 28;
                name_box.append(preview_label);
            }

            header.append(name_box);

            var count_label = new Label("%u".printf(notifications.length()));
            count_label.add_css_class("notification-group-badge");
            count_label.set_size_request(20, 20);
            count_label.halign = Align.CENTER;
            count_label.valign = Align.CENTER;
            header.append(count_label);

            var clear_btn = new Button.from_icon_name("edit-clear-all-symbolic");
            clear_btn.add_css_class("flat");
            clear_btn.add_css_class("circular");
            clear_btn.tooltip_text = _("Clear all");
            // Collect IDs as owned primitives - never capture unowned list in closures
            uint[] ids = {};
            foreach (var n in notifications) ids += n.id;
            clear_btn.clicked.connect(() => {
                unowned var mgr = SystemMonitor.get_default().notifications;
                foreach (var id in ids) mgr.remove_from_history(id);
            });
            header.append(clear_btn);

            expand_icon = new Image.from_icon_name("pan-down-symbolic");
            expand_icon.pixel_size = 12;
            var expand_btn = new Button();
            expand_btn.add_css_class("flat");
            expand_btn.add_css_class("circular");
            expand_btn.set_child(expand_icon);
            header.append(expand_btn);
            append(header);

            revealer = new Revealer();
            revealer.transition_type = RevealerTransitionType.SLIDE_DOWN;
            revealer.reveal_child = false;

            var items_box = new Box(Orientation.VERTICAL, 0);
            var sep = new Separator(Orientation.HORIZONTAL);
            sep.add_css_class("notification-group-sep");
            items_box.append(sep);
            foreach (var notif in notifications) {
                var item = new NotificationItem(notif);
                item.add_css_class("notification-group-item");
                items_box.append(item);
            }
            revealer.set_child(items_box);
            append(revealer);

            expand_btn.clicked.connect(toggle_expand);

            var click = new GestureClick();
            click.button = 1;
            click.released.connect((n, x, y) => {
                var widget = header.pick(x, y, PickFlags.DEFAULT);
                if (widget is Button) return;
                toggle_expand();
            });
            header.add_controller(click);
        }

        private void toggle_expand() {
            expanded = !expanded;
            revealer.reveal_child = expanded;
            expand_icon.icon_name = expanded ? "pan-up-symbolic" : "pan-down-symbolic";
        }
    }

    public class NotificationItem : Box {

        public NotificationItem(Notification notif) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class("notification-item-card");

            // Header: Icon + App Name + Time
            var header = new Box(Orientation.HORIZONTAL, 8);
            header.margin_top = 10;
            header.margin_start = 12;
            header.margin_end = 10;

            var icon_img = new Image();
            icon_img.pixel_size = 16;
            load_notification_icon(icon_img, notif.icon, notif.app_name);
            header.append(icon_img);

            var app_label = new Label(notif.app_name);
            app_label.add_css_class("caption");
            app_label.add_css_class("dim-label");
            app_label.hexpand = true;
            app_label.halign = Align.START;
            header.append(app_label);

            var time_label = new Label(format_time(notif.timestamp));
            time_label.add_css_class("caption");
            time_label.add_css_class("dim-label");
            header.append(time_label);

            var close_btn = new Button.from_icon_name("window-close-symbolic");
            close_btn.add_css_class("flat");
            close_btn.add_css_class("circular");
            close_btn.clicked.connect(() => {
                SystemMonitor.get_default().notifications.remove_from_history(notif.id);
            });
            header.append(close_btn);
            append(header);

            // Content
            var content_box = new Box(Orientation.VERTICAL, 2);
            content_box.margin_start = 12;
            content_box.margin_end = 12;
            content_box.margin_bottom = 12;
            content_box.margin_top = 4;

            if (notif.summary != "") {
                var summary = new Label(notif.summary);
                summary.add_css_class("bold");
                summary.halign = Align.START;
                summary.wrap = true;
                summary.xalign = 0;
                content_box.append(summary);
            }

            if (notif.body != "") {
                var body = new Label(notif.body);
                body.add_css_class("caption");
                body.halign = Align.START;
                body.wrap = true;
                body.xalign = 0;
                content_box.append(body);
            }
            append(content_box);

            // Actions
            if (notif.actions.length > 0) {
                var actions_box = new Box(Orientation.HORIZONTAL, 4);
                actions_box.homogeneous = true;
                actions_box.margin_bottom = 8;
                actions_box.margin_start = 8;
                actions_box.margin_end = 8;

                for (int i = 0; i < notif.actions.length; i += 2) {
                    if (i + 1 < notif.actions.length) {
                        string key = notif.actions[i];
                        string label = notif.actions[i+1];
                        if (key == "default") continue;

                        var btn = new Button.with_label(label);
                        btn.add_css_class("flat");
                        btn.clicked.connect(() => {
                            SystemMonitor.get_default().notifications.invoke_action(notif.id, key);
                        });
                        actions_box.append(btn);
                    }
                }
                if (actions_box.get_first_child() != null) {
                    append(actions_box);
                }
            }
        }

        private string format_time(int64 timestamp) {
            var now = GLib.get_real_time();
            var diff = (now - timestamp) / 1000000;

            if (diff < 60) return "Just now";
            if (diff < 3600) return "%dm ago".printf((int)(diff / 60));
            if (diff < 86400) return "%dh ago".printf((int)(diff / 3600));
            return "Old";
        }
    }

    // Resolve notification icon with fallback chain:
    // 1. Absolute path, load from file
    // 2. Themed icon name that exists in current theme, use it
    // 3. Try GIO app lookup by app_name, use app's gicon
    // 4. dialog-information-symbolic

    public static void load_notification_icon(Image img, string icon_str, string app_name) {
        // 1. Absolute path
        if (icon_str.has_prefix("/")) {
            try {
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale(icon_str, 48, 48, true);
                img.paintable = Gdk.Texture.for_pixbuf(pixbuf);
                return;
            } catch {}
        } else if (icon_str.has_prefix("file://")) {
            try {
                var path = GLib.Filename.from_uri(icon_str);
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale(path, 48, 48, true);
                img.paintable = Gdk.Texture.for_pixbuf(pixbuf);
                return;
            } catch {}
        }

        // 2. Themed icon present in theme
        if (icon_str != "") {
            var theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
            if (theme.has_icon(icon_str)) {
                img.icon_name = icon_str;
                return;
            }
        }

        // 3. GIO app lookup by display name or desktop id. Match loosely so
        //    apps that pass "TelegramDesktop" still resolve to Telegram.
        if (app_name != "") {
            string needle = app_name.down();
            string needle_compact = needle.replace(" ", "").replace("-", "").replace("_", "");
            foreach (var info in GLib.AppInfo.get_all()) {
                string nm = info.get_name().down();
                string nm_compact = nm.replace(" ", "").replace("-", "").replace("_", "");
                string aid = info.get_id().down();
                if (aid.has_suffix(".desktop"))
                    aid = aid.substring(0, aid.length - ".desktop".length);
                string aid_compact = aid.replace(".", "").replace("-", "").replace("_", "");
                if (nm.contains(needle) ||
                    needle.contains(nm) ||
                    nm_compact.contains(needle_compact) ||
                    needle_compact.contains(nm_compact) ||
                    aid_compact.contains(needle_compact) ||
                    needle_compact.contains(aid_compact)) {
                    var gicon = info.get_icon();
                    if (gicon != null) {
                        img.gicon = gicon;
                        return;
                    }
                }
            }
        }

        // 4. Generic fallback - last resort only.
        img.icon_name = "dialog-information-symbolic";
    }
}
