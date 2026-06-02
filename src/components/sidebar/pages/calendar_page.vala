using Gtk;
using Singularity.Widgets;

namespace Singularity {

    public class CalendarPage : Box {
        public signal void back_clicked();

        public CalendarPage() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class("calendar-notifications-page");

            // Calendar Section (Clean, no frame)
            var calendar_section = new Box(Orientation.VERTICAL, 0);
            calendar_section.margin_start = 10;
            calendar_section.margin_end = 10;

            var calendar = new Singularity.Shell.CalendarView();
            // We'll style the calendar-view to be transparent via CSS
            calendar_section.append(calendar);

            append(calendar_section);
        }
    }
}
