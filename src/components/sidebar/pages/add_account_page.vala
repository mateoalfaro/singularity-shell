using Gtk;
using Singularity.Widgets;

namespace Singularity.SidebarPages {

    public class AddAccountPage : SettingsPage {
        private SettingsView view;
        private Stack inner_stack;
        private Box login_box;
        private EntryRow nc_user;
        private PasswordRow nc_pass;
        private EntryRow nc_server;
        private Label error_label;
        private Button connect_btn;
        private string selected_provider = "";

        public signal void account_added();

        public AddAccountPage(SettingsView view) {
            base(_("Add Account"));
            this.view = view;
            back_btn.visible = true;
            back_clicked.connect(() => {
                view.navigate_to("accounts");
            });

            inner_stack = new Stack();
            inner_stack.transition_type = StackTransitionType.SLIDE_LEFT_RIGHT;

            var providers_box = build_provider_list();
            inner_stack.add_named(providers_box, "providers");

            login_box = new Box(Orientation.VERTICAL, 0);
            inner_stack.add_named(login_box, "login");

            add_widget(inner_stack);
        }

        private Widget build_provider_list() {
            var group = new PreferencesGroup();
            group.add_row(create_provider_row("Google", "google", "goa-account-google"));
            group.add_row(create_provider_row("Nextcloud", "owncloud", "goa-account-owncloud"));
            group.add_row(create_provider_row("Microsoft", "exchange", "goa-account-exchange"));
            group.add_row(create_provider_row("IMAP/SMTP", "imap_smtp", "goa-account-email"));
            return group;
        }

        private Widget create_provider_row(string name, string id, string icon_name) {
            var row = new ActionRow(name, null, icon_name);
            var arrow = new Image.from_icon_name("go-next-symbolic");
            arrow.add_css_class("dim-label");
            row.add_suffix(arrow);
            row.activated.connect(() => {
                select_provider(id, name);
            });
            return row;
        }

        private void select_provider(string id, string name) {
            selected_provider = id;
            Widget? child = login_box.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                login_box.remove(child);
                child = next;
            }
            if (id == "owncloud" || id == "nextcloud") {
                build_nextcloud_form();
            } else {
                build_generic_connect_form(name, id);
            }
            inner_stack.visible_child_name = "login";
        }

        private void build_nextcloud_form() {
            var group = new PreferencesGroup(_("Server"));
            nc_server = new EntryRow("Server Address");
            nc_server.text = "https://";
            group.add_row(nc_server);
            login_box.append(group);

            var cred_group = new PreferencesGroup(_("Credentials"));
            nc_user = new EntryRow("Username");
            cred_group.add_row(nc_user);
            nc_pass = new PasswordRow("Password");
            nc_pass.entry_activated.connect(on_connect_clicked);
            cred_group.add_row(nc_pass);
            login_box.append(cred_group);

            error_label = new Label("");
            error_label.add_css_class("error");
            error_label.wrap = true;
            error_label.margin_top = 12;
            error_label.margin_start = 12;
            error_label.margin_end = 12;
            login_box.append(error_label);

            connect_btn = new Button.with_label(_("Connect"));
            connect_btn.add_css_class("suggested-action");
            connect_btn.add_css_class("pill");
            connect_btn.halign = Align.CENTER;
            connect_btn.margin_top = 24;
            connect_btn.clicked.connect(on_connect_clicked);
            login_box.append(connect_btn);
        }

        private void build_generic_connect_form(string name, string provider_id) {
            var group = new PreferencesGroup();
            var row = new ActionRow(name, _("Click Connect to sign in with your %s account.").printf(name), "goa-account-%s".printf(provider_id));
            group.add_row(row);
            login_box.append(group);

            error_label = new Label("");
            error_label.add_css_class("error");
            error_label.wrap = true;
            error_label.margin_top = 12;
            error_label.margin_start = 12;
            error_label.margin_end = 12;
            login_box.append(error_label);

            connect_btn = new Button.with_label(_("Connect"));
            connect_btn.add_css_class("suggested-action");
            connect_btn.add_css_class("pill");
            connect_btn.halign = Align.CENTER;
            connect_btn.margin_top = 24;
            connect_btn.clicked.connect(on_connect_clicked);
            login_box.append(connect_btn);
        }

        private void on_connect_clicked() {
            if (selected_provider == "owncloud") {
                perform_nextcloud_login.begin();
            } else {
                perform_provider_login.begin();
            }
        }

        private async void perform_provider_login() {
            connect_btn.sensitive = false;
            error_label.label = _("Contacting provider...");
            try {
                var provider = global::Goa.BackendProvider.get_for_provider_type(selected_provider);
                if (provider == null) {
                    error_label.label = _("Provider not supported");
                    connect_btn.sensitive = true;
                    return;
                }
                var client = yield new global::Goa.Client(null);
                var object = yield provider.add_account(client, null);
                if (object != null) {
                    message("Account added: %s", object.get_object_path());
                    account_added();
                    view.navigate_to("accounts");
                } else {
                    error_label.label = _("Account creation cancelled");
                    connect_btn.sensitive = true;
                }
            } catch (GLib.Error e) {
                error_label.label = _("Failed: ") + e.message;
                connect_btn.sensitive = true;
            }
        }

        private async void perform_nextcloud_login() {
            string server = nc_server.text;
            string user = nc_user.text;
            string pass = nc_pass.text;
            if (server == "" || user == "" || pass == "") {
                error_label.label = _("Please fill in all fields");
                return;
            }
            connect_btn.sensitive = false;
            error_label.label = _("Connecting...");
            try {
                var client = yield new global::Goa.Client(null);
                var manager = client.get_manager();
                var creds_builder = new VariantBuilder(new VariantType("a{sv}"));
                creds_builder.add("{sv}", "password", new Variant.string(pass));
                var credentials = creds_builder.end();
                var details_builder = new VariantBuilder(new VariantType("a{ss}"));
                details_builder.add("{ss}", "Uri", server);
                details_builder.add("{ss}", "AcceptSslErrors", "false");
                var details = details_builder.end();
                string identity = user;
                string presentation = user + "@" + server.replace("https://", "").replace("http://", "").split("/")[0];
                string object_path;
                yield manager.call_add_account(
                    selected_provider,
                    identity,
                    presentation,
                    credentials,
                    details,
                    null,
                    out object_path
                );
                message("Account added: %s", object_path);
                account_added();
                view.navigate_to("accounts");
            } catch (GLib.Error e) {
                error_label.label = _("Failed to connect: ") + e.message;
                connect_btn.sensitive = true;
            }
        }
    }
}