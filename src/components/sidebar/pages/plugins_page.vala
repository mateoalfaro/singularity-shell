using Gtk;
using Singularity.Widgets;
using Peas;

namespace Singularity {

    public class PluginsPage : SettingsPage {
        private PluginManager manager;
        private PreferencesGroup active_group;
        private PreferencesGroup inactive_group;
        private SettingsView view;
        private List<PluginRow> plugin_rows = new List<PluginRow>();

        private class PluginRow {
            public PreferencesRow row;
            public Peas.PluginInfo info;
            public PluginRow(PreferencesRow r, Peas.PluginInfo i) { row = r; info = i; }
        }

        public PluginsPage(SettingsView view) {
            base(_("Plugins"));
            this.view = view;

            back_clicked.connect(() => {
                view.go_home();
            });

             // Search
            var search = new Singularity.Widgets.SearchEntry();
            search.placeholder_text = _("Search plugins...");
            search.search_changed.connect(on_search_changed);
            add_widget(search);

            manager = PluginManager.get_default();

            active_group = new PreferencesGroup(_("Active Plugins"), _("Currently enabled extensions"));
            inactive_group = new PreferencesGroup(_("Inactive Plugins"), _("Disabled extensions"));
            add_group(active_group);
            add_group(inactive_group);

            refresh_list();

            // Add refresh button
            var refresh_btn = new Button.from_icon_name("view-refresh-symbolic");
            refresh_btn.add_css_class("flat");
            refresh_btn.tooltip_text = _("Reload Plugins");
            refresh_btn.clicked.connect(() => {
                Peas.Engine.get_default().rescan_plugins();
                refresh_list();
            });
            header.append(refresh_btn);
        }

        private void refresh_list() {
            active_group.clear();
            inactive_group.clear();
            plugin_rows = new List<PluginRow>();

            var plugins = manager.get_available_plugins();
            if (plugins == null) {
                 var label = new Label(_("No plugins found"));
                 label.add_css_class("dim-label");
                 active_group.add_row(label);
                 active_group.visible = true;
                 inactive_group.visible = false;
                 return;
            }

            int active_count = 0;
            int inactive_count = 0;

            foreach (var info in plugins) {
                if (info.is_hidden()) continue;

                string name = info.get_name();
                string module = info.get_module_name();
                bool enabled = manager.is_plugin_enabled(module);

                var row = new ActionRow(name);

                var icon = new Image.from_icon_name("application-x-addon-symbolic");
                icon.pixel_size = 32;
                icon.margin_end = 12;
                row.add_prefix(icon);

                var btn = new Button.from_icon_name("emblem-system-symbolic");
                btn.add_css_class("circular-button");
                btn.tooltip_text = _("Plugin Settings");
                btn.valign = Align.CENTER;
                btn.clicked.connect(() => {
                     view.open_plugin_details(info);
                });
                row.add_suffix(btn);

                if (enabled) {
                    active_group.add_row(row);
                    active_count++;
                } else {
                    inactive_group.add_row(row);
                    inactive_count++;
                }
                plugin_rows.append(new PluginRow(row, info));
            }

            active_group.visible = active_count > 0;
            inactive_group.visible = inactive_count > 0;
        }

        private void on_search_changed(Singularity.Widgets.SearchEntry entry) {
            string query = entry.text.down();
            foreach (var item in plugin_rows) {
                bool match = item.info.get_name().down().contains(query);
                if (!match && item.info.get_description() != null) {
                    match = item.info.get_description().down().contains(query);
                }
                item.row.visible = match;
            }
        }
    }
}
