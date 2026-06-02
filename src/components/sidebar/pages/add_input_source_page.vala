using Gtk;
using Gnome;
using Singularity.Widgets;

namespace Singularity.SidebarPages {

    public class AddInputSourcePage : SettingsPage {
        public signal void source_selected(string id, string name);
        private XkbInfo xkb_info;
        private List<InputSourceInfo> all_sources;
        private Singularity.Widgets.SearchEntry search_entry;
        private PreferencesGroup list_group;
        private class InputSourceInfo {
            public string id;
            public string name;
            public string description;

            public InputSourceInfo(string id, string name, string description) {
                this.id = id;
                this.name = name;
                this.description = description;
            }
        }

        public AddInputSourcePage(SettingsView view) {
            base(_("Add Input Source"));
            back_clicked.connect(() => {
                view.navigate_to("keyboard");
            });
            xkb_info = new XkbInfo();
            all_sources = new List<InputSourceInfo>();
            search_entry = new Singularity.Widgets.SearchEntry();
            search_entry.placeholder_text = _("Search languages...");
            search_entry.search_changed.connect(filter_list);
            add_widget(search_entry);
            list_group = new PreferencesGroup(_("Available Layouts"));
            add_group(list_group);
            Idle.add(() => {
                load_sources();
                return false;
            });
        }

        private void load_sources() {
            var layouts = xkb_info.get_all_layouts();
            foreach (var layout_id in layouts) {
                string name;
                string short_desc;
                string xkb_layout;
                string xkb_variant;
                if (xkb_info.get_layout_info(layout_id, out name, out short_desc, out xkb_layout, out xkb_variant)) {
                    all_sources.append(new InputSourceInfo(layout_id, name, short_desc));
                }
            }
            all_sources.sort((a, b) => {
                return a.name.collate(b.name);
            });
            populate_list();
        }

        private void populate_list() {
            filter_list(search_entry);
        }

        private void filter_list(Singularity.Widgets.SearchEntry entry) {
            list_group.clear();
            string query = entry.text.down();
            int count = 0;
            foreach (var source in all_sources) {
                if (query == "" || source.name.down().contains(query) || source.description.down().contains(query)) {
                    var row = new ActionRow(source.name, source.description);
                    var btn = new Button.from_icon_name("list-add-symbolic");
                    btn.add_css_class("circular-button");
                    btn.valign = Align.CENTER;
                    btn.clicked.connect(() => {
                        source_selected(source.id, source.name);
                    });
                    row.add_suffix(btn);
                    row.activatable = true;
                    var gesture = new GestureClick();
                    gesture.released.connect(() => {
                        source_selected(source.id, source.name);
                    });
                    row.add_controller(gesture);
                    list_group.add_row(row);
                    count++;
                    if (count > 50) break;
                }
            }
        }
    }
}
