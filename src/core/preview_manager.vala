using GLib;
using Gtk;

namespace Singularity {

    [DBus (name = "dev.sinty.shell.Preview")]
    public class PreviewManager : Object {
        private PreviewDialog? dialog = null;
        private Gtk.Application app;

        public PreviewManager(Gtk.Application app) {
            this.app = app;
            try {
                var connection = Bus.get_sync(BusType.SESSION);
                connection.register_object("/dev/sinty/shell/Preview", this);
            } catch (Error e) {
                warning("Failed to register PreviewManager on DBus: %s", e.message);
            }
        }

        public void show_preview(string uri) throws Error {
            var file = File.new_for_uri(uri);
            try {
                var info = file.query_info("standard::*,standard::icon,standard::content-type", FileQueryInfoFlags.NONE);
                Idle.add(() => {
                    if (dialog == null) {
                        dialog = new PreviewDialog(app);
                    }
                    dialog.show_file(file, info);
                    return false;
                });
            } catch (Error e) {
                throw e;
            }
        }

        public void close_preview() throws Error {
            Idle.add(() => {
                if (dialog != null) {
                    dialog.close_dialog();
                }
                return false;
            });
        }
    }
}
