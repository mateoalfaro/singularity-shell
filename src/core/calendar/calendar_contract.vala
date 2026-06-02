using GLib;

namespace Singularity.Calendar {

    public struct CalendarEvent {
        public string id;
        public string title;
        public string description;
        public DateTime start_time;
        public DateTime end_time;
        public string color;
        public bool all_day;
    }
    public interface CalendarProvider : Object {
        public abstract string name { get; }
        public abstract string id { get; }
        public abstract string color { get; }
        public abstract bool is_visible { get; set; }
        public signal void events_changed();
        public abstract async Gee.List<CalendarEvent?> get_events(DateTime start, DateTime end) throws Error;
        public abstract async void import_file(string path) throws Error;
    }
    public class CalendarManager : Object {
        private static CalendarManager? _instance;
        private Gee.ArrayList<CalendarProvider> providers;

        public static CalendarManager get_default() {
            if (_instance == null) {
                _instance = new CalendarManager();
            }
            return _instance;
        }

        private CalendarManager() {
            providers = new Gee.ArrayList<CalendarProvider>();
        }

        public void load_local_calendars() {
            string data_dir = Environment.get_user_data_dir();
            string calendar_dir = GLib.Path.build_filename(data_dir, "singularity", "calendar");
            try {
                var dir = File.new_for_path(calendar_dir);
                if (!dir.query_exists()) {
                    DirUtils.create_with_parents(calendar_dir, 0755);
                }
                if (get_provider("local-provider") == null) {
                    register_provider(new LocalProvider());
                }
                var enumerator = dir.enumerate_children(FileAttribute.STANDARD_NAME, 0);
                FileInfo info;
                while ((info = enumerator.next_file()) != null) {
                    string filename = info.get_name();
                    if (filename.has_suffix(".json") && filename != "local.json") {
                        string name = filename.replace(".json", "");
                        string id = "local-" + name;
                        if (get_provider(id) != null) continue;
                        string color = generate_color(name);
                        register_provider(new LocalProvider(name, id, filename, color));
                    }
                }
            } catch (Error e) {
                warning("Failed to load local calendars: %s", e.message);
            }
        }

        public static string generate_color(string seed) {
            uint hash = seed.hash();
            int r = (int)((hash & 0xFF0000) >> 16);
            int g = (int)((hash & 0x00FF00) >> 8);
            int b = (int)(hash & 0x0000FF);
            return "#%02x%02x%02x".printf((r % 156) + 50, (g % 156) + 50, (b % 156) + 50);
        }
        public signal void events_changed();

        public void register_provider(CalendarProvider provider) {
            providers.add(provider);
            provider.events_changed.connect(() => {
                events_changed();
            });
        }

        public void unregister_provider(string id) {
            var provider = get_provider(id);
            if (provider != null) {
                providers.remove(provider);
                events_changed();
            }
        }

        public CalendarProvider? get_provider(string id) {
            foreach (var p in providers) {
                if (p.id == id) return p;
            }
            return null;
        }

        public Gee.List<CalendarProvider> get_providers() {
            return providers;
        }

        public async Gee.List<CalendarEvent?> get_events(DateTime start, DateTime end) {
            var all_events = new Gee.ArrayList<CalendarEvent?>();
            foreach (var provider in providers) {
                if (!provider.is_visible) continue;
                try {
                    var events = yield provider.get_events(start, end);
                    all_events.add_all(events);
                } catch (Error e) {
                    warning("Failed to fetch events from %s: %s", provider.name, e.message);
                }
            }
            return all_events;
        }

        /** Add an event to the local calendar. */

        public void add_local_event(CalendarEvent evt) {
            var local = get_provider("local-provider") as Singularity.Calendar.LocalProvider;
            if (local != null) local.add_event(evt);
        }

        /** Delete an event by id from the local calendar. */

        public void delete_local_event(string id) {
            var local = get_provider("local-provider") as Singularity.Calendar.LocalProvider;
            if (local != null) local.delete_event(id);
        }

        /** Update an existing local event (matched by id). */

        public void update_local_event(CalendarEvent evt) {
            var local = get_provider("local-provider") as Singularity.Calendar.LocalProvider;
            if (local != null) local.update_event(evt);
        }
    }
}
