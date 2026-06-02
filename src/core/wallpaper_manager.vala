using Gtk;
using Gdk;
using GLib;

namespace Singularity {

    public class WallpaperManager : Object {
        private static WallpaperManager? _instance = null;
        private GLib.Settings settings;
        public string? wallpaper_path { get; private set; }
        public Texture? display_texture { get; private set; }
        public Texture? preview_texture { get; private set; }
        public Texture? medium_texture { get; private set; }
        private string? _cached_path = null;
        private int _load_serial = 0;
        private Mutex _mutex = Mutex ();

        public signal void wallpaper_changed();

        public static WallpaperManager get_default() {
            if (_instance == null) {
                _instance = new WallpaperManager();
            }
            return _instance;
        }

        private WallpaperManager() {
            settings = new GLib.Settings("dev.sinty.desktop");
            settings.changed["background-picture-uri"].connect(() => {
                reload();
            });
            reload();
        }

        public void reload() {
            string custom_uri = settings.get_string("background-picture-uri");
            string? path = resolve_path(custom_uri);
            if (path == null) {
                string[] fallbacks = {};
                foreach (unowned string d in GLib.Environment.get_system_data_dirs()) {
                    fallbacks += GLib.Path.build_filename(d, "backgrounds", "singularity", "singularity-cosmos.svg");
                    fallbacks += GLib.Path.build_filename(d, "backgrounds", "singularity", "default.png");
                }
                fallbacks += "../default.png";
                foreach (unowned string d in GLib.Environment.get_system_data_dirs())
                    fallbacks += GLib.Path.build_filename(d, "backgrounds", "default.png");
                fallbacks += "/usr/share/backgrounds/gnome/adwaita-l.jpg";
                foreach (var p in fallbacks) {
                    if (FileUtils.test(p, FileTest.EXISTS)) {
                        path = p;
                        break;
                    } else {
                        if (!p.has_prefix("/")) {
                            try {
                                string exe_path = FileUtils.read_link("/proc/self/exe");
                                var exe_dir = File.new_for_path(exe_path).get_parent();
                                var f = exe_dir.get_child(p);
                                if (f.query_exists()) {
                                    path = f.get_path();
                                    break;
                                }
                            } catch (Error e) {}
                        }
                    }
                }
            }
            if (path != null) {
                if (path == _cached_path) return;
                _cached_path = path;
                wallpaper_path = path;

                int serial;
                _mutex.lock();
                _load_serial++;
                serial = _load_serial;
                _mutex.unlock();

                string load_path = path;
                int target_w = 0;
                int target_h = 0;
                get_display_target_size(out target_w, out target_h);

                new Thread<void>("wallpaper-load", () => {
                    _mutex.lock();
                    if (serial != _load_serial) {
                        _mutex.unlock();
                        return;
                    }
                    _mutex.unlock();

                    Pixbuf? pb_display = null;
                    try {
                        pb_display = load_display_pixbuf(load_path, target_w, target_h);
                    } catch (Error e) {
                        warning("Failed to load wallpaper: %s", e.message);
                    }

                    Pixbuf? pb_medium = null;
                    Pixbuf? pb_small = null;
                    try {
                        pb_medium = new Pixbuf.from_file_at_scale(load_path, 320, 180, true);
                    } catch (Error e) {}
                    try {
                        pb_small = new Pixbuf.from_file_at_scale(load_path, 120, 67, false);
                    } catch (Error e) {}

                    _mutex.lock();
                    bool stale = (serial != _load_serial);
                    _mutex.unlock();
                    if (stale) return;

                    Idle.add(() => {
                        _mutex.lock();
                        bool still_valid = (serial == _load_serial);
                        _mutex.unlock();
                        if (!still_valid) return false;

                        if (pb_display != null) display_texture = Texture.for_pixbuf(pb_display);
                        if (pb_medium != null) medium_texture = Texture.for_pixbuf(pb_medium);
                        if (pb_small != null) preview_texture = Texture.for_pixbuf(pb_small);
                        message("Wallpaper loaded: %s", load_path);
                        wallpaper_changed();
                        return false;
                    });
                });
            }
        }

        private string? resolve_path(string uri) {
            if (uri == "") return null;
            try {
                var file = File.new_for_uri(uri);
                var path = file.get_path();
                if (path != null && FileUtils.test(path, FileTest.EXISTS)) {
                    return path;
                }
            } catch (Error e) {
            }
            return null;
        }

        private void get_display_target_size(out int target_w, out int target_h) {
            target_w = 0;
            target_h = 0;
            var display = Gdk.Display.get_default();
            if (display == null) return;
            var monitors = display.get_monitors();
            for (uint i = 0; i < monitors.get_n_items(); i++) {
                var monitor = monitors.get_item(i) as Gdk.Monitor;
                if (monitor == null) continue;
                var geom = monitor.geometry;
                int scale = monitor.scale_factor;
                target_w = int.max(target_w, geom.width * scale);
                target_h = int.max(target_h, geom.height * scale);
            }
        }

        private Pixbuf load_display_pixbuf(string path, int target_w, int target_h) throws Error {
            if (target_w <= 0 || target_h <= 0) {
                target_w = 1920;
                target_h = 1080;
            }

            int src_w = 0;
            int src_h = 0;
            Gdk.Pixbuf.get_file_info(path, out src_w, out src_h);
            if (src_w <= 0 || src_h <= 0) {
                return new Pixbuf.from_file_at_scale(path, target_w, target_h, true);
            }

            double scale = double.max((double)target_w / (double)src_w,
                                      (double)target_h / (double)src_h);
            int decode_w = int.max(1, (int)Math.ceil(src_w * scale));
            int decode_h = int.max(1, (int)Math.ceil(src_h * scale));
            return new Pixbuf.from_file_at_scale(path, decode_w, decode_h, true);
        }
    }
}
