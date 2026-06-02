using GLib;
using Gtk;

namespace Singularity {

    public class AppSearchProvider : GLib.Object, SearchProvider {
        public string id { get { return "apps"; } }
        public string name { get { return "Applications"; } }

        public AppSearchProvider() {
            Object();
        }

        // Returns true if all chars of needle appear in haystack in order.
        private static bool fuzzy_match(string haystack, string needle) {
            int h = 0;
            int n = 0;
            unowned uint8[] hb = haystack.data;
            unowned uint8[] nb = needle.data;
            while (h < hb.length && n < nb.length) {
                if (hb[h] == nb[n]) n++;
                h++;
            }
            return n == nb.length;
        }

        // Score a single word against an app.
        private double score_word(string word, string name, string app_id_str, string? exec, string? desc) {
            if (name == word) return 100.0;
            if (name.has_prefix(word)) return 85.0;

            // Any word in name starts with query word
            string[] name_words = name.split(" ");
            foreach (var nw in name_words) {
                if (nw.has_prefix(word)) return 80.0;
            }

            if (name.contains(word)) return 65.0;
            if (fuzzy_match(name, word)) return 45.0;
            if (app_id_str.contains(word) || (exec != null && exec.contains(word))) return 40.0;

            if (desc != null) {
                string[] desc_words = desc.split(" ");
                foreach (var dw in desc_words) {
                    if (dw.has_prefix(word)) return 25.0;
                }
                if (desc.contains(word)) return 20.0;
                if (fuzzy_match(desc, word)) return 12.0;
            }

            return 0.0;
        }

        public async List<SearchResult> search(string query, Cancellable? cancellable) throws Error {
            var results = new List<SearchResult>();
            if (query.length < 1) return results;

            string query_down = query.down().strip();
            var app_system = AppSystem.get_default();
            // Use the list AppSystem already scanned (and refreshes on directory
            // changes) rather than re-parsing every .desktop per keystroke; only
            // scan here if that cache is somehow empty.
            unowned List<AppInfo> apps = app_system.get_all_apps();
            if (apps == null || apps.length() == 0) {
                app_system.scan_apps();
                apps = app_system.get_all_apps();
            }

            foreach (var app in apps) {
                if (cancellable != null && cancellable.is_cancelled()) break;
                if (!app.should_show()) continue;

                string name = app.get_display_name().down();
                string? desc = app.get_description() != null ? app.get_description().down() : null;
                string? exec = app.get_executable() != null ? app.get_executable().down() : null;
                string app_id_str = app.get_id() != null ? app.get_id().down() : "";

                double score = 0.0;

                string[] words = query_down.split(" ");
                // Filter out empty strings from split
                var non_empty = new GLib.List<string>();
                foreach (var w in words) {
                    if (w.strip() != "") non_empty.append(w.strip());
                }

                if (non_empty.length() > 1) {
                    // Multi-word: average the best score per word, scaled by 0.9
                    double total = 0.0;
                    bool all_match = true;
                    foreach (var w in non_empty) {
                        double ws = score_word(w, name, app_id_str, exec, desc);
                        if (ws <= 0.0) { all_match = false; break; }
                        total += ws;
                    }
                    if (all_match) {
                        score = (total / (double)non_empty.length()) * 0.9;
                    }
                } else {
                    score = score_word(query_down, name, app_id_str, exec, desc);
                }

                if (score > 0) {
                    var res = new SearchResult(
                        this,
                        app.get_display_name(),
                        app.get_description(),
                        null,
                        app.get_icon(),
                        app.get_id()
                    );
                    res.score = score;

                    res.activated.connect(() => {
                        AppSystem.launch_app(app);
                    });

                    results.append(res);
                }
            }

            return results;
        }
    }
}
