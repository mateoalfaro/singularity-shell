using Gtk;
using Singularity.Widgets;

namespace Singularity {

    public class PreviewDialog : Singularity.Shell.ShellDialog {
        private File file;
        private FileInfo info;
        private Box dialog_container;

        public PreviewDialog(Gtk.Application app) {
            Object(application: app);
            set_default_size(600, 500);
        }

        public void show_file(File file, FileInfo info) {
            this.file = file;
            this.info = info;
            if (content_box.get_first_child() != null) {
                content_box.remove(content_box.get_first_child());
            }
            build_ui();
            load_preview();
            present();
        }

        private void build_ui() {
            dialog_container = new Box(Orientation.VERTICAL, 0);
            dialog_container.add_css_class("preview-dialog");
            content_box.append(dialog_container);
            var header = new Box(Orientation.HORIZONTAL, 12);
            header.add_css_class("dialog-header");
            header.margin_top = 12;
            header.margin_start = 12;
            header.margin_end = 12;
            header.margin_bottom = 0;
            var title_box = new Box(Orientation.VERTICAL, 2);
            title_box.hexpand = true;
            var title = new Label(info.get_display_name());
            title.add_css_class("dialog-title");
            title.halign = Align.START;
            title.ellipsize = Pango.EllipsizeMode.END;
            var subtitle = new Label(format_size(info.get_size()));
            subtitle.add_css_class("dialog-subtitle");
            subtitle.halign = Align.START;
            title_box.append(title);
            title_box.append(subtitle);
            header.append(title_box);
            var close_btn = new CloseButton();
            close_btn.clicked.connect(close_dialog);
            header.append(close_btn);
            dialog_container.append(header);
            var preview_area = new Box(Orientation.VERTICAL, 0);
            preview_area.vexpand = true;
            preview_area.hexpand = true;
            preview_area.margin_top = 12;
            preview_area.margin_bottom = 12;
            preview_area.margin_start = 12;
            preview_area.margin_end = 12;
            preview_area.add_css_class("preview-area");
            dialog_container.append(preview_area);
            this.preview_box = preview_area;
            var footer = new Box(Orientation.HORIZONTAL, 12);
            footer.margin_bottom = 12;
            footer.margin_start = 12;
            footer.margin_end = 12;
            footer.halign = Align.END;
            var open_btn = new Button.with_label(_("Open"));
            open_btn.add_css_class("suggested-action");
            open_btn.clicked.connect(() => {
                try {
                    AppInfo.launch_default_for_uri(file.get_uri(), null);
                    close_dialog();
                } catch (Error e) {
                    warning("Failed to open file: %s", e.message);
                }
            });
            footer.append(open_btn);
            dialog_container.append(footer);
        }
        private Box preview_box;

        private void load_preview() {
            string content_type = info.get_content_type();
            if (content_type.has_prefix("image/")) {
                load_image_preview();
            } else if (content_type.has_prefix("text/") || content_type == "application/javascript" || content_type == "application/json") {
                load_text_preview();
            } else {
                load_generic_preview();
            }
        }

        private void load_image_preview() {
            try {
                var pic = new Picture.for_filename(file.get_path() ?? "");
                pic.content_fit = ContentFit.CONTAIN;
                pic.vexpand = true;
                pic.hexpand = true;
                pic.add_css_class("preview-image");
                preview_box.append(pic);
            } catch (Error e) {
                load_generic_preview();
            }
        }

        private void load_text_preview() {
            try {
                var scroll = new ScrolledWindow();
                scroll.vexpand = true;
                scroll.hexpand = true;
                scroll.add_css_class("preview-text-scroll");
                var text_view = new TextView();
                text_view.editable = false;
                text_view.cursor_visible = false;
                text_view.monospace = true;
                text_view.wrap_mode = WrapMode.WORD;
                text_view.left_margin = 8;
                text_view.right_margin = 8;
                text_view.top_margin = 8;
                text_view.bottom_margin = 8;
                var stream = new DataInputStream(file.read());
                uint8[] buffer = new uint8[4096];
                size_t read;
                stream.read_all(buffer, out read);
                string text = ((string)buffer).substring(0, (long)read);
                if (!text.validate()) {
                    text = "[Binary or invalid encoding]";
                }
                text_view.buffer.text = text;
                scroll.set_child(text_view);
                preview_box.append(scroll);
            } catch (Error e) {
                load_generic_preview();
            }
        }

        private void load_generic_preview() {
            var box = new Box(Orientation.VERTICAL, 12);
            box.valign = Align.CENTER;
            box.halign = Align.CENTER;
            var img = new Image();
            img.pixel_size = 128;
            img.set_from_gicon(info.get_icon());
            img.add_css_class("preview-icon");
            var label = new Label(info.get_content_type());
            label.add_css_class("dim-label");
            box.append(img);
            box.append(label);
            preview_box.append(box);
        }

        private string format_size(int64 size) {
            if (size < 1024) return "%lld B".printf(size);
            if (size < 1024 * 1024) return "%.1f KB".printf(size / 1024.0);
            if (size < 1024 * 1024 * 1024) return "%.1f MB".printf(size / (1024.0 * 1024.0));
            return "%.1f GB".printf(size / (1024.0 * 1024.0 * 1024.0));
        }
    }
}
