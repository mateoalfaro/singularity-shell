using Gee;

namespace Singularity.Core {

    public class EditThemes : Object {

        public static ArrayList<Singularity.Widgets.ColorTheme> get_all() {
            var themes = new ArrayList<Singularity.Widgets.ColorTheme>();
            themes.add(new Singularity.Widgets.ColorTheme(
                "auto",
                "Auto (Accent)",
                "#1e1e2e",
                "#cdd6f4",
                {
                    "#1e1e2e", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#cdd6f4",
                    "#313244", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#cdd6f4"
                }
            ));
            themes.add(new Singularity.Widgets.ColorTheme(
                "dracula",
                "Dracula",
                "#282a36",
                "#f8f8f2",
                {
                    "#282a36", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                    "#282a36", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2"
                }
            ));
            themes.add(new Singularity.Widgets.ColorTheme(
                "oblivion",
                "Oblivion",
                "#2e3436",
                "#d3d7cf",
                {
                    "#2e3436", "#cc0000", "#4e9a06", "#c4a000", "#3465a4", "#75507b", "#06989a", "#d3d7cf",
                    "#555753", "#ef2929", "#8ae234", "#fce94f", "#729fcf", "#ad7fa8", "#34e2e2", "#eeeeec"
                }
            ));
            themes.add(new Singularity.Widgets.ColorTheme(
                "cobalt",
                "Cobalt",
                "#002240",
                "#ffffff",
                {
                    "#002240", "#ff0000", "#3ad900", "#ff9d00", "#0088ff", "#ff0044", "#00ddff", "#ffffff",
                    "#002240", "#ff0000", "#3ad900", "#ff9d00", "#0088ff", "#ff0044", "#00ddff", "#ffffff"
                }
            ));
            themes.add(new Singularity.Widgets.ColorTheme(
                "kate",
                "Kate",
                "#ffffff",
                "#000000",
                {
                    "#ffffff", "#b00000", "#008000", "#e0c000", "#0000c0", "#800080", "#008080", "#000000",
                    "#ffffff", "#b00000", "#008000", "#e0c000", "#0000c0", "#800080", "#008080", "#000000"
                }
            ));
            themes.add(new Singularity.Widgets.ColorTheme(
                "solarized-dark",
                "Solarized Dark",
                "#002b36",
                "#839496",
                {
                    "#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                    "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"
                }
            ));
            themes.add(new Singularity.Widgets.ColorTheme(
                "solarized-light",
                "Solarized Light",
                "#fdf6e3",
                "#657b83",
                {
                    "#eee8d5", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#073642",
                    "#fdf6e3", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#002b36"
                }
            ));
            themes.add(new Singularity.Widgets.ColorTheme(
                "tango",
                "Tango",
                "#ffffff",
                "#2e3436",
                {
                    "#2e3436", "#cc0000", "#4e9a06", "#c4a000", "#3465a4", "#75507b", "#06989a", "#d3d7cf",
                    "#555753", "#ef2929", "#8ae234", "#fce94f", "#729fcf", "#ad7fa8", "#34e2e2", "#eeeeec"
                }
            ));
            themes.add(new Singularity.Widgets.ColorTheme(
                "classic",
                "Classic",
                "#ffffff",
                "#000000",
                {
                    "#ffffff", "#cc0000", "#4e9a06", "#c4a000", "#3465a4", "#75507b", "#06989a", "#d3d7cf",
                    "#555753", "#ef2929", "#8ae234", "#fce94f", "#729fcf", "#ad7fa8", "#34e2e2", "#eeeeec"
                }
            ));
            return themes;
        }
    }
}
