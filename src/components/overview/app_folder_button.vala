using Gtk;
using GLib;

namespace Singularity {

    public class AppFolderButton : Box {
        private AppSystem app_system;
        private string folder_id;
        private Grid preview_grid;
        private Gtk.Image[] preview_images;
        private Label name_label;
        private Button btn;

        public signal void clicked(string folder_id);
        public signal void drop_app(string folder_id, string app_id);

        public AppFolderButton(string folder_id) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.folder_id = folder_id;
            app_system = AppSystem.get_default();

            btn = new Button();            btn.add_css_class("app-grid-item");
            btn.add_css_class("folder-button");
            btn.has_frame = false;

            var inner = new Box(Orientation.VERTICAL, 6);
            inner.halign = Align.CENTER;
            inner.valign = Align.CENTER;

            // 2x2 icon preview grid inside a rounded box
            var preview_box = new Box(Orientation.VERTICAL, 0);
            preview_box.add_css_class("folder-button-box");
            preview_box.set_size_request(72, 72);
            preview_box.halign = Align.CENTER;
            preview_box.valign = Align.CENTER;

            preview_grid = new Grid();
            preview_grid.halign = Align.CENTER;
            preview_grid.valign = Align.CENTER;
            preview_grid.column_spacing = 4;
            preview_grid.row_spacing = 4;
            preview_grid.margin_start = 8;
            preview_grid.margin_end = 8;
            preview_grid.margin_top = 8;
            preview_grid.margin_bottom = 8;

            preview_images = new Gtk.Image[4];
            for (int i = 0; i < 4; i++) {
                preview_images[i] = new Gtk.Image();
                preview_images[i].pixel_size = 24;
                preview_images[i].icon_name = "application-x-executable-symbolic";
                preview_grid.attach(preview_images[i], i % 2, i / 2, 1, 1);
            }

            preview_box.append(preview_grid);
            inner.append(preview_box);

            name_label = new Label(get_folder_name());
            name_label.add_css_class("folder-button-label");
            name_label.max_width_chars = 12;
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.xalign = 0.5f;
            inner.append(name_label);

            btn.set_child(inner);
            append(btn);

            btn.clicked.connect(() => this.clicked(folder_id));

            // Drop target: accept app IDs dropped onto this folder
            var drop = new DropTarget(typeof(string), Gdk.DragAction.MOVE);
            drop.drop.connect((val, x, y) => {
                string? app_id = val.get_string();
                if (app_id != null) drop_app(folder_id, app_id);
                return true;
            });
            drop.enter.connect((x, y) => {
                btn.add_css_class("drag-over");
                return Gdk.DragAction.MOVE;
            });
            drop.leave.connect(() => btn.remove_css_class("drag-over"));
            btn.add_controller(drop);

            // Drag source: drag folder itself (prefix folder:)
            var drag = new DragSource();
            drag.actions = Gdk.DragAction.MOVE;
            drag.prepare.connect((x, y) => {
                return new Gdk.ContentProvider.for_value("folder:" + folder_id);
            });
            drag.drag_begin.connect((d) => {
                var theme = IconTheme.get_for_display(Gdk.Display.get_default());
                var p = theme.lookup_icon("folder", null, 48, 1, TextDirection.NONE, 0);
                if (p != null) drag.set_icon(p, 24, 24);
            });
            btn.add_controller(drag);

            ulong folders_sid = app_system.folders_changed.connect(refresh);
            this.destroy.connect(() => { app_system.disconnect(folders_sid); });
            refresh();
        }

        private string get_folder_name() {
            var folder = app_system.get_folder(folder_id);
            return folder != null ? folder.name : "Folder";
        }

        public void refresh() {
            name_label.label = get_folder_name();
            var folder = app_system.get_folder(folder_id);
            if (folder == null) return;
            var theme = IconTheme.get_for_display(Gdk.Display.get_default());
            for (int i = 0; i < 4; i++) {
                if (i < folder.app_ids.length) {
                    var app = app_system.get_app_info(folder.app_ids[i]);
                    bool set = false;
                    if (app != null) {
                        var gicon = app.get_icon();
                        if (gicon is ThemedIcon) {
                            foreach (var name in ((ThemedIcon)gicon).get_names()) {
                                if (theme != null && theme.has_icon(name)) {
                                    preview_images[i].icon_name = name;
                                    set = true;
                                    break;
                                }
                            }
                        }
                        if (!set && gicon != null) {
                            preview_images[i].set_from_gicon(gicon);
                            set = true;
                        }
                    }
                    if (!set) preview_images[i].icon_name = "application-x-executable-symbolic";
                    preview_images[i].visible = true;
                } else {
                    preview_images[i].visible = false;
                }
            }
        }
    }
}
