[CCode (cheader_filename = "mpv/client.h")]
namespace Mpv {
    [CCode (cname = "mpv_handle", free_function = "mpv_terminate_destroy")]
    [Compact]
    public class Client {
        [CCode (cname = "mpv_create")]
        public Client ();

        [CCode (cname = "mpv_initialize")]
        public int initialize ();

        [CCode (cname = "mpv_command")]
        public int command ([CCode (array_length = false)] string[] args);

        [CCode (cname = "mpv_command_string")]
        public int command_string (string args);

        [CCode (cname = "mpv_set_option")]
        public int set_option (string name, Format format, void* data);

        [CCode (cname = "mpv_set_option_string")]
        public int set_option_string (string name, string data);
        
        [CCode (cname = "mpv_get_property")]
        public int get_property (string name, Format format, void* data);

        [CCode (cname = "mpv_set_property")]
        public int set_property (string name, Format format, void* data);

        [CCode (cname = "mpv_get_property_string")]
        public string get_property_string (string name);

        [CCode (cname = "mpv_set_property_string")]
        public int set_property_string (string name, string data);
        
        [CCode (cname = "mpv_observe_property")]
        public int observe_property (uint64 reply_userdata, string name, Format format);
        
        [CCode (cname = "mpv_unobserve_property")]
        public int unobserve_property (uint64 registered_reply_userdata);

        [CCode (cname = "mpv_wait_event")]
        public Event* wait_event (double timeout);
        
        [CCode (cname = "mpv_request_log_messages")]
        public int request_log_messages (string min_level);
    }

    [CCode (cname = "mpv_format", cprefix = "MPV_FORMAT_", has_type_id = false)]
    public enum Format {
        NONE,
        STRING,
        OSD_STRING,
        FLAG,
        INT64,
        DOUBLE,
        NODE,
        NODE_ARRAY,
        NODE_MAP,
        BYTE_ARRAY
    }

    [CCode (cname = "mpv_event_id", cprefix = "MPV_EVENT_", has_type_id = false)]
    public enum EventId {
        NONE,
        SHUTDOWN,
        LOG_MESSAGE,
        GET_PROPERTY_REPLY,
        SET_PROPERTY_REPLY,
        COMMAND_REPLY,
        START_FILE,
        END_FILE,
        FILE_LOADED,
        IDLE,
        TICK,
        CLIENT_MESSAGE,
        VIDEO_RECONFIG,
        AUDIO_RECONFIG,
        METADATA_UPDATE,
        SEEK,
        PLAYBACK_RESTART,
        PROPERTY_CHANGE,
        CHAPTER_CHANGE,
        QUEUE_OVERFLOW,
        HOOK
    }

    [CCode (cname = "mpv_event", has_type_id = false)]
    public struct Event {
        public EventId event_id;
        public int error;
        public uint64 reply_userdata;
        public void* data;
    }
}
