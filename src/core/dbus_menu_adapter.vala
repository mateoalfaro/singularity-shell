using GLib;
using Dbusmenu;

namespace Singularity {

    public class DBusMenuAdapter : MenuModel {
        private Dbusmenu.Client client;
        private Dbusmenu.Menuitem? item;
        private unowned List<Dbusmenu.Menuitem> children;
        private bool is_root;

        public DBusMenuAdapter(Dbusmenu.Client client, Dbusmenu.Menuitem? item, bool is_root = false) {
            this.client = client;
            this.item = item;
            this.is_root = is_root;

            if (item != null) {
                update_children();
                item.child_added.connect(on_child_added);
                item.child_moved.connect(on_child_moved);
                item.child_removed.connect(on_child_removed);
                item.property_changed.connect(on_property_changed);
            }

            if (is_root) {
                 client.layout_updated.connect(on_layout_updated);
            }
        }

        private void update_children() {
            if (item != null) {
                children = item.get_children();
            } else {
                children = null;
            }
        }

        private void on_child_added(Dbusmenu.Menuitem item, GLib.Object child, uint position) {
            update_children();
            items_changed((int)position, 0, 1);
        }

        private void on_child_removed(Dbusmenu.Menuitem item, GLib.Object child) {
            int old_n = get_n_items() + 1;
            update_children();
            items_changed(0, old_n, get_n_items());
        }

        private void on_child_moved(Dbusmenu.Menuitem item, GLib.Object child, uint newpos, uint oldpos) {
            update_children();
            items_changed(0, get_n_items(), get_n_items());
        }

        private void on_property_changed(string prop, Variant val) {
            // A visible/label/enabled property changed on one of our children -
            // signal a full refresh so menu consumers re-read all item attributes.
            items_changed(0, get_n_items(), get_n_items());
        }

        private void on_layout_updated(Dbusmenu.Client client) {
            if (item == null) {
                item = client.get_root();
                if (item != null) {
                    item.child_added.connect(on_child_added);
                    item.child_moved.connect(on_child_moved);
                    item.child_removed.connect(on_child_removed);
                    item.property_changed.connect(on_property_changed);
                }
            }
            update_children();
            items_changed(0, get_n_items(), get_n_items());
        }

        public override int get_n_items() {
            return (int) (children != null ? children.length() : 0);
        }

        public override Variant? get_item_attribute_value(int item_index, string attribute, VariantType? expected_type) {
             if (children == null || item_index < 0 || item_index >= children.length()) return null;
             var child = children.nth_data(item_index);

             if (attribute == "label") {
                 string val = child.property_get(Dbusmenu.MENUITEM_PROP_LABEL);
                 return new Variant.string(val ?? "");
             }
             if (attribute == "action") {
                 // We use a namespaced action
                 return new Variant.string("dbusmenu.activate");
             }
             if (attribute == "target") {
                 return new Variant.int32(child.get_id());
             }
             if (attribute == "enabled") {
                 bool enabled = child.property_get_bool(Dbusmenu.MENUITEM_PROP_ENABLED);
                 return new Variant.boolean(enabled);
             }
             if (attribute == "visible") {
                 bool visible = child.property_get_bool(Dbusmenu.MENUITEM_PROP_VISIBLE);
                 return new Variant.boolean(visible);
             }
             return null;
        }

        public override MenuModel? get_item_link(int item_index, string link) {
             if (link != "submenu") return null;
             if (children == null || item_index < 0 || item_index >= children.length()) return null;

             var child = children.nth_data(item_index);
             if (child.get_children() == null || child.get_children().length() == 0) return null;

             return new DBusMenuAdapter(client, child, false);
        }
    }
}
