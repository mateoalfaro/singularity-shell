[CCode (cprefix = "Goa", lower_case_cprefix = "goa_", cheader_filename = "goabackend/goabackend.h")]
namespace Goa {

    [CCode (cname = "GoaProvider", type_id = "goa_provider_get_type ()")]
    public class BackendProvider : GLib.Object {
        [CCode (cname = "goa_provider_get_for_provider_type")]
        public static unowned BackendProvider? get_for_provider_type (string provider_type);
        [CCode (cname = "goa_provider_add_account", finish_name = "goa_provider_add_account_finish")]
        public async Goa.Object add_account (Goa.Client client, void* parent = null, GLib.Cancellable? cancellable = null) throws GLib.Error;
    }
}