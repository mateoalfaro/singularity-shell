using Gtk;
using Singularity.Widgets;

namespace Singularity {

    public class NotificationsPage : SettingsPage {

        public NotificationsPage() {
            base(_("Notifications"));

            var clear_btn = new Button.from_icon_name("user-trash-symbolic");
            clear_btn.add_css_class("flat");
            clear_btn.add_css_class("circular");
            clear_btn.tooltip_text = _("Clear All");
            clear_btn.clicked.connect(() => {
                SystemMonitor.get_default().notifications.clear_history();
            });
            header.append(clear_btn);

            var nc = new NotificationCenter();
            nc.vexpand = true;
            add_widget(nc);
        }
    }
}
