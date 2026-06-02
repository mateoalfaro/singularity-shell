using Gtk;
using Singularity.Widgets;

namespace Singularity.SidebarPages {

    public class DefaultAppsPage : SettingsPage {

        public DefaultAppsPage(SettingsView view) {
            base(_("Default Apps"));
            back_btn.visible = true;
            back_clicked.connect(() => view.navigate_to("apps"));

            build_simple_group("Internet", {
                { "Web Browser",  "web-browser-symbolic",         { "x-scheme-handler/http", "x-scheme-handler/https" } },
                { "Mail Client",  "mail-send-symbolic",           { "x-scheme-handler/mailto" } },
            });
            build_simple_group("Files & Text", {
                { "File Manager", "system-file-manager-symbolic", { "inode/directory" } },
                { "Text Editor",  "text-editor-symbolic",         { "text/plain" } },
            });
            build_media_group(
                "Images", "image-x-generic-symbolic",
                { "image/jpeg", "image/png", "image/gif", "image/webp", "image/svg+xml", "image/tiff", "image/bmp", "image/heic", "image/heif", "image/avif" },
                {
                    { "JPEG",  "image-x-generic-symbolic", { "image/jpeg" } },
                    { "PNG",   "image-x-generic-symbolic", { "image/png" } },
                    { "GIF",   "image-x-generic-symbolic", { "image/gif" } },
                    { "WebP",  "image-x-generic-symbolic", { "image/webp" } },
                    { "SVG",   "image-x-generic-symbolic", { "image/svg+xml" } },
                    { "TIFF",  "image-x-generic-symbolic", { "image/tiff" } },
                    { "BMP",   "image-x-generic-symbolic", { "image/bmp" } },
                }
            );
            build_media_group(
                "Video", "video-x-generic-symbolic",
                { "video/mp4", "video/x-matroska", "video/x-msvideo", "video/webm", "video/quicktime", "video/mpeg", "video/ogg" },
                {
                    { "MP4",  "video-x-generic-symbolic", { "video/mp4" } },
                    { "MKV",  "video-x-generic-symbolic", { "video/x-matroska" } },
                    { "AVI",  "video-x-generic-symbolic", { "video/x-msvideo" } },
                    { "WebM", "video-x-generic-symbolic", { "video/webm" } },
                    { "MOV",  "video-x-generic-symbolic", { "video/quicktime" } },
                }
            );
            build_media_group(
                "Music", "audio-x-generic-symbolic",
                { "audio/mpeg", "audio/flac", "audio/ogg", "audio/wav", "audio/aac", "audio/x-vorbis+ogg" },
                {
                    { "MP3",  "audio-x-generic-symbolic", { "audio/mpeg" } },
                    { "FLAC", "audio-x-generic-symbolic", { "audio/flac" } },
                    { "OGG",  "audio-x-generic-symbolic", { "audio/ogg" } },
                    { "WAV",  "audio-x-generic-symbolic", { "audio/wav" } },
                    { "AAC",  "audio-x-generic-symbolic", { "audio/aac" } },
                }
            );
            build_simple_group("Documents", {
                { "PDF",           "x-office-document-symbolic",     { "application/pdf" } },
                { "Word (.docx)",  "x-office-document-symbolic",     { "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/msword" } },
                { "Excel (.xlsx)", "x-office-spreadsheet-symbolic",  { "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/vnd.ms-excel" } },
                { "PowerPoint",    "x-office-presentation-symbolic", { "application/vnd.openxmlformats-officedocument.presentationml.presentation", "application/vnd.ms-powerpoint" } },
                { "ODT",           "x-office-document-symbolic",     { "application/vnd.oasis.opendocument.text" } },
                { "ODS",           "x-office-spreadsheet-symbolic",  { "application/vnd.oasis.opendocument.spreadsheet" } },
                { "ODP",           "x-office-presentation-symbolic", { "application/vnd.oasis.opendocument.presentation" } },
                { "EPUB",          "x-office-document-symbolic",     { "application/epub+zip" } },
            });
            build_simple_group("Archives", {
                { "ZIP",  "package-x-generic-symbolic", { "application/zip" } },
                { "TAR",  "package-x-generic-symbolic", { "application/x-tar" } },
                { "GZ",   "package-x-generic-symbolic", { "application/gzip" } },
                { "7-Zip","package-x-generic-symbolic", { "application/x-7z-compressed" } },
                { "RAR",  "package-x-generic-symbolic", { "application/x-rar-compressed" } },
            });
            build_custom_group();
        }

        // Helpers

        private struct MimeCat {
            public string label;
            public string icon;
            public string[] mimes;
        }

        // Flat group: one SelectionRow per entry
        private void build_simple_group(string title, MimeCat[] cats) {
            var group = new PreferencesGroup(title);
            foreach (var cat in cats)
                group.add_row(make_selection_row(cat.label, cat.icon, cat.mimes));
            add_group(group);
        }

        // Media group: one _("All X") SelectionRow + ExpanderRow with per-format rows
        private void build_media_group(string title, string generic_icon,
                                        string[] all_mimes, MimeCat[] formats) {
            var group = new PreferencesGroup(title);

            // Build child format rows first so we can reference them
            var format_rows = new Gee.ArrayList<SelectionRow>();
            var expander = new ExpanderRow(_("Individual formats"));
            foreach (var fmt in formats) {
                var row = make_selection_row(fmt.label, fmt.icon, fmt.mimes);
                var sel = row as SelectionRow;
                if (sel != null) format_rows.add(sel);
                expander.add_row(row);
            }

            // "All X" row - when selected, also refresh all child rows visually
            var all_widget = make_selection_row(title, generic_icon, all_mimes);
            var all_sel = all_widget as SelectionRow;
            if (all_sel != null) {
                all_sel.selected.connect((item) => {
                    foreach (var child_sel in format_rows) {
                        child_sel.current_value = item;
                    }
                });
            }
            group.add_row(all_widget);
            group.add_row(expander);

            add_group(group);
        }

        private Widget make_selection_row(string label, string fallback_icon, string[] mimes) {
            var candidates = AppInfo.get_recommended_for_type(mimes[0]);
            if (candidates == null || candidates.length() == 0)
                candidates = AppInfo.get_all_for_type(mimes[0]);

            string[] names = {};
            string[] subtitles = {};
            GLib.Icon?[] icons = {};
            AppInfo[] infos = {};
            foreach (var ai in candidates) {
                names += ai.get_name();
                string? desc = ai.get_description();
                if (desc == null || desc.strip() == "") {
                    string id = ai.get_id() ?? "";
                    if (id.has_suffix(".desktop")) id = id[0:id.length - 8];
                    desc = id;
                }
                subtitles += desc;
                icons += ai.get_icon();
                infos += ai;
            }

            var current = AppInfo.get_default_for_type(mimes[0], false);

            if (names.length == 0) {
                var r = new ActionRow(label);
                r.subtitle = _("No apps found");
                r.sensitive = false;
                var ic = new Image.from_icon_name(fallback_icon);
                ic.pixel_size = 32; ic.margin_end = 8;
                r.add_prefix(ic);
                return r;
            }

            string[] captured_mimes = mimes;
            AppInfo[] captured_infos = infos;

            var sel = new SelectionRow.with_details(
                label, names, subtitles, icons,
                current != null ? current.get_name() : ""
            );

            var ic = new Image();
            ic.pixel_size = 32; ic.margin_end = 8;
            if (current != null && current.get_icon() != null)
                ic.gicon = current.get_icon();
            else
                ic.icon_name = fallback_icon;
            sel.add_prefix(ic);

            sel.selected.connect((item) => {
                for (int j = 0; j < captured_infos.length; j++) {
                    if (captured_infos[j].get_name() != item) continue;
                    var app_icon = captured_infos[j].get_icon();
                    ic.gicon = app_icon ?? (GLib.Icon) new ThemedIcon(fallback_icon);
                    try {
                        foreach (var m in captured_mimes)
                            captured_infos[j].set_as_default_for_type(m);
                    } catch (Error e) {
                        warning("set_as_default_for_type failed: %s", e.message);
                    }
                    break;
                }
            });
            return sel;
        }

        // Custom group

        private void build_custom_group() {
            var group = new PreferencesGroup(_("Custom"));
            group.description = "Manually associate a MIME type with an app";

            var mime_row = new ActionRow(_("MIME Type"));
            var mime_entry = new Entry();
            mime_entry.placeholder_text = _("e.g. application/x-custom");
            mime_entry.hexpand = true;
            mime_entry.valign = Align.CENTER;
            mime_row.add_suffix(mime_entry);

            var app_row = new ActionRow(_("Application"));
            var app_label = new Label(_("Choose…"));
            app_label.add_css_class("dim-label");
            var app_btn = new Button();
            app_btn.add_css_class("flat");
            app_btn.child = app_label;
            app_btn.valign = Align.CENTER;
            AppInfo? chosen_app = null;
            app_btn.clicked.connect(() => {
                var dialog = new AppChooserDialog.for_content_type(
                    get_root() as Gtk.Window ?? null,
                    DialogFlags.MODAL,
                    mime_entry.get_text() == "" ? "*" : mime_entry.get_text()
                );
                dialog.response.connect((id) => {
                    if (id == ResponseType.OK) {
                        chosen_app = dialog.get_app_info();
                        app_label.label = chosen_app != null ? chosen_app.get_name() : _("Choose…");
                        app_label.remove_css_class("dim-label");
                    }
                    dialog.destroy();
                });
                dialog.present();
            });
            app_row.add_suffix(app_btn);

            var apply_row = new ActionRow("");
            var apply_btn = new Button.with_label(_("Apply"));
            apply_btn.add_css_class("suggested-action");
            apply_btn.valign = Align.CENTER;
            apply_btn.clicked.connect(() => {
                string mime = mime_entry.get_text().strip();
                if (mime == "" || chosen_app == null) return;
                try {
                    chosen_app.set_as_default_for_type(mime);
                    mime_entry.text = "";
                    app_label.label = _("Choose…");
                    app_label.add_css_class("dim-label");
                    chosen_app = null;
                } catch (Error e) {
                    warning("Custom default set failed: %s", e.message);
                }
            });
            apply_row.add_suffix(apply_btn);

            group.add_row(mime_row);
            group.add_row(app_row);
            group.add_row(apply_row);
            add_group(group);
        }
    }
}
