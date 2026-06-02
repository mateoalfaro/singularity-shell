using Gtk;
using Singularity.Widgets;

namespace Singularity.SidebarPages {
    public class PerformancePage : SettingsPage {
        private GLib.Settings _settings;

        public PerformancePage(SettingsView view) {
            base(_("Performance"));
            back_clicked.connect(() => view.go_home());
            _settings = new GLib.Settings("dev.sinty.desktop");

            var gm = GameModeManager.get_default();

            // Game Mode
            var gm_group = new PreferencesGroup(_("Game Mode"));
            gm_group.description = gm.available
                ? "gamemode daemon detected"
                : "Install gamemode for GPU/CPU performance boost in games";

            var auto_row = new SwitchRow(_("Auto Game Mode"),
                "Activate performance mode automatically when a fullscreen game is detected");
            auto_row.sensitive = gm.available;
            auto_row.active = gm.auto_mode;
            auto_row.switch_btn.notify["active"].connect(() => {
                _settings.set_boolean("gamemode-auto", auto_row.active);
            });
            gm_group.add_row(auto_row);

            var manual_row = new SwitchRow(_("Game Mode Active"),
                "Manually force performance mode right now");
            manual_row.sensitive = gm.available;
            manual_row.active = gm.active;
            manual_row.switch_btn.notify["active"].connect(() => {
                if (manual_row.active) gm.activate("manual");
                else gm.deactivate();
            });
            gm_group.add_row(manual_row);

            gm.state_changed.connect(() => {
                manual_row.active = gm.active;
                auto_row.sensitive = gm.available;
                manual_row.sensitive = gm.available;
            });

            add_group(gm_group);

            // MangoHud
            bool mangohud_available = GLib.Environment.find_program_in_path("mangohud") != null;
            var hud_group = new PreferencesGroup(_("MangoHud"));
            hud_group.description = mangohud_available
                ? "MangoHud detected - overlay for FPS, temps and more"
                : "Install MangoHud for in-game performance overlay";

            var hud_auto_row = new SwitchRow(_("Auto MangoHud"),
                "Inject MangoHud overlay when launching games via the shell");
            hud_auto_row.sensitive = mangohud_available;
            hud_auto_row.active = mangohud_available && _settings.get_boolean("mangohud-auto");
            hud_auto_row.switch_btn.notify["active"].connect(() => {
                _settings.set_boolean("mangohud-auto", hud_auto_row.active);
            });
            hud_group.add_row(hud_auto_row);
            add_group(hud_group);

            // Power profile. The platform profiles (Power Saver, Balanced,
            // Performance) go through power-profiles-daemon, which sets the CPU
            // governor and platform tuning itself and handles polkit. Extreme
            // Save is Singularity's own profile on top: it also dims the screen
            // and disables animations (ExtremeModeManager) over PPD power-saver.
            // Same four-state model as the system quick-settings tile.
            var ppm = SystemMonitor.get_default().power_profiles;
            var extreme = ExtremeModeManager.get_default();
            var profile_group = new PreferencesGroup(_("Power Profile"));
            profile_group.description = "Extreme Save also dims the screen and disables animations";
            string[] labels = { "Extreme Save", "Power Saver", "Balanced", "Performance" };
            var profile_row = new SelectionRow(_("Profile"), labels, current_profile_label(ppm, extreme));
            profile_row.selected.connect((item) => {
                apply_profile_label(ppm, extreme, item);
            });
            profile_group.add_row(profile_row);
            add_group(profile_group);

            // Display link
            var display_group = new PreferencesGroup(_("Display"));
            var vrr_link = new ActionRow(_("Variable Refresh Rate (VRR)"), _("Configure VRR in Display settings"), "video-display-symbolic");
            vrr_link.activatable = true;
            vrr_link.activated.connect(() => view.navigate_to("displays"));
            display_group.add_row(vrr_link);
            add_group(display_group);
        }

        // Label for the current state: Extreme Save wins over the PPD profile.
        private static string current_profile_label(PowerProfilesManager ppm, ExtremeModeManager extreme) {
            if (extreme.active) return "Extreme Save";
            switch (ppm.active_profile) {
                case "power-saver": return "Power Saver";
                case "performance": return "Performance";
                default:            return "Balanced";
            }
        }

        // Apply a chosen label, mirroring the system tile: Extreme Save turns on
        // extreme mode over PPD power-saver; the others turn it off and set the
        // matching PPD profile.
        private void apply_profile_label(PowerProfilesManager ppm, ExtremeModeManager extreme, string label) {
            switch (label) {
                case "Extreme Save":
                    extreme.set_extreme_mode(true);
                    ppm.set_profile("power-saver");
                    break;
                case "Power Saver":
                    extreme.set_extreme_mode(false);
                    ppm.set_profile("power-saver");
                    break;
                case "Balanced":
                    extreme.set_extreme_mode(false);
                    ppm.set_profile("balanced");
                    break;
                case "Performance":
                    extreme.set_extreme_mode(false);
                    ppm.set_profile("performance");
                    break;
            }
        }
    }
}
