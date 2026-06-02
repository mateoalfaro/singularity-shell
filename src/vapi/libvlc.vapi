[CCode (cheader_filename = "vlc/vlc.h")]
namespace LibVLC {
    [Compact]
    [CCode (cname = "libvlc_instance_t", free_function = "libvlc_release")]
    public class Instance {
        [CCode (cname = "libvlc_new")]
        public Instance (int argc, [CCode (array_length = false)] string[]? argv);
    }

    [Compact]
    [CCode (cname = "libvlc_media_t", free_function = "libvlc_media_release")]
    public class Media {
        [CCode (cname = "libvlc_media_new_path")]
        public Media (Instance instance, string path);
        [CCode (cname = "libvlc_media_new_location")]
        public Media.from_location (Instance instance, string location);
    }

    [Compact]
    [CCode (cname = "libvlc_media_player_t", free_function = "libvlc_media_player_release")]
    public class MediaPlayer {
        [CCode (cname = "libvlc_media_player_new")]
        public MediaPlayer (Instance instance);
        
        [CCode (cname = "libvlc_media_player_set_media")]
        public void set_media (Media media);
        
        [CCode (cname = "libvlc_media_player_play")]
        public int play ();
        
        [CCode (cname = "libvlc_media_player_pause")]
        public void pause ();
        
        [CCode (cname = "libvlc_media_player_stop")]
        public void stop ();
        
        [CCode (cname = "libvlc_media_player_set_xwindow")]
        public void set_xwindow (uint32 xid);
        
        [CCode (cname = "libvlc_media_player_get_time")]
        public int64 get_time ();
        
        [CCode (cname = "libvlc_media_player_set_time")]
        public void set_time (int64 time);
        
        [CCode (cname = "libvlc_media_player_get_length")]
        public int64 get_length ();
        
        [CCode (cname = "libvlc_media_player_get_position")]
        public float get_position ();
        
        [CCode (cname = "libvlc_media_player_set_position")]
        public void set_position (float position);
        
        [CCode (cname = "libvlc_media_player_get_volume")]
        public int get_volume ();
        
        [CCode (cname = "libvlc_media_player_set_volume")]
        public int set_volume (int volume);
    }
}
