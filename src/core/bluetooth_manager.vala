using GLib;

namespace Singularity {

    [DBus (name = "org.freedesktop.DBus.ObjectManager")]
    public interface ObjectManager : Object {
        public abstract HashTable<ObjectPath, HashTable<string, HashTable<string, Variant>>> get_managed_objects () throws Error;
        public signal void interfaces_added (ObjectPath object_path, HashTable<string, HashTable<string, Variant>> interfaces_and_properties);
        public signal void interfaces_removed (ObjectPath object_path, string[] interfaces);
    }
    [DBus (name = "org.bluez.Adapter1")]
    public interface Adapter1 : Object {
        public abstract bool powered { get; set; }
        public abstract bool discovering { get; set; }
        public abstract string name { owned get; }
        public abstract string address { owned get; }
        public abstract async void start_discovery () throws Error;
        public abstract async void stop_discovery () throws Error;
        public abstract async void remove_device (ObjectPath device) throws Error;
    }
    [DBus (name = "org.bluez.Device1")]
    public interface Device1 : Object {
        public abstract string name { owned get; }
        public abstract string alias { owned get; }
        public abstract string address { owned get; }
        public abstract string icon { owned get; }
        public abstract bool paired { get; }
        public abstract bool connected { get; }
        public abstract bool trusted { get; set; }
        public abstract bool blocked { get; set; }
        public abstract int16 rssi { get; }
        public abstract async void connect () throws Error;
        public abstract async void disconnect () throws Error;
        public abstract async void pair () throws Error;
        public abstract async void cancel_pairing () throws Error;
    }
    public class BluetoothManager : Object {
        public struct DeviceInfo {
            public string path;
            public string name;
            public string address;
            public string icon;
            public bool paired;
            public bool connected;
            public int rssi;
        }
        private ObjectManager? object_manager;
        private Adapter1? adapter;
        private string adapter_path;
        public bool is_available { get; private set; default = false; }
        public bool is_powered { get; private set; default = false; }
        public bool is_discovering { get; private set; default = false; }
        public List<DeviceInfo?> devices;
        public signal void state_changed();
        public signal void device_added(DeviceInfo device);
        public signal void device_removed(string path);
        public signal void device_changed(string path);

        public BluetoothManager() {
            devices = new List<DeviceInfo?>();
            init_bluez();
        }

        private async void init_bluez() {
            try {
                object_manager = yield Bus.get_proxy(BusType.SYSTEM, "org.bluez", "/");
                if (object_manager != null) {
                    message("BluetoothManager: Connected to org.bluez ObjectManager");
                    object_manager.interfaces_added.connect(on_interfaces_added);
                    object_manager.interfaces_removed.connect(on_interfaces_removed);
                    var objects = object_manager.get_managed_objects();
                    objects.foreach((path, interfaces) => {
                        if (interfaces.contains("org.bluez.Adapter1")) {
                            setup_adapter(path);
                        }
                        if (interfaces.contains("org.bluez.Device1")) {
                            var props = interfaces.get("org.bluez.Device1");
                            add_device(path, props != null ? props.lookup("Name") : null);
                        }
                    });
                } else {
                    warning("BluetoothManager: ObjectManager proxy is null");
                }
            } catch (Error e) {
                warning("Failed to connect to BlueZ: %s", e.message);
            }
        }

        private async void setup_adapter(string path) {
            try {
                adapter = yield Bus.get_proxy(BusType.SYSTEM, "org.bluez", path);
                adapter_path = path;
                is_available = true;
                adapter.notify["powered"].connect(() => {
                    is_powered = adapter.powered;
                    state_changed();
                });
                adapter.notify["discovering"].connect(() => {
                    is_discovering = adapter.discovering;
                    state_changed();
                });
                is_powered = adapter.powered;
                is_discovering = adapter.discovering;
                state_changed();
            } catch (Error e) {
                warning("Failed to setup adapter: %s", e.message);
            }
        }

        private void on_interfaces_added(ObjectPath path, HashTable<string, HashTable<string, Variant>> interfaces) {
            if (interfaces.contains("org.bluez.Adapter1") && adapter == null) {
                setup_adapter(path);
            }
            if (interfaces.contains("org.bluez.Device1")) {
                var props = interfaces.get("org.bluez.Device1");
                add_device(path, props != null ? props.lookup("Name") : null);
            }
        }

        private void on_interfaces_removed(ObjectPath path, string[] interfaces) {
            foreach (var iface in interfaces) {
                if (iface == "org.bluez.Adapter1" && path == adapter_path) {
                    adapter = null;
                    is_available = false;
                    state_changed();
                }
                if (iface == "org.bluez.Device1") {
                    remove_device_from_list(path);
                }
            }
        }

        private void add_device(string path, Variant? properties) {
            if (properties == null) return;
            create_device_proxy.begin(path);
        }

        private async void create_device_proxy(string path) {
            try {
                var device = yield Bus.get_proxy<Device1>(BusType.SYSTEM, "org.bluez", path);
                if (device != null) {
                    DeviceInfo info = DeviceInfo();
                    info.path = path;
                    info.name = device.name ?? device.alias ?? device.address;
                    info.address = device.address;
                    info.icon = device.icon ?? "bluetooth-active-symbolic";
                    info.paired = device.paired;
                    info.connected = device.connected;
                    info.rssi = device.rssi;
                    devices.append(info);
                    device_added(info);
                    device.notify.connect((pspec) => {
                        update_device_info(path, device);
                    });
                }
            } catch (Error e) {
                warning("Failed to create device proxy: %s", e.message);
            }
        }

        private void update_device_info(string path, Device1 device) {
            for (int i = 0; i < devices.length(); i++) {
                var d = devices.nth_data(i);
                if (d.path == path) {
                    DeviceInfo updated = DeviceInfo();
                    updated.path = path;
                    updated.name = device.name ?? device.alias ?? device.address;
                    updated.address = d.address;
                    updated.icon = d.icon;
                    updated.connected = device.connected;
                    updated.paired = device.paired;
                    updated.rssi = device.rssi;
                    devices.remove(d);
                    devices.insert(updated, i);
                    break;
                }
            }
            device_changed(path);
        }

        private void remove_device_from_list(string path) {
            for (int i = 0; i < devices.length(); i++) {
                var d = devices.nth_data(i);
                if (d.path == path) {
                    devices.remove(d);
                    device_removed(path);
                    return;
                }
            }
        }

        public async void set_power(bool power) {
            if (adapter != null) {
                adapter.powered = power;
            }
        }

        public async void start_discovery() {
            if (adapter != null) {
                try {
                    yield adapter.start_discovery();
                } catch (Error e) {
                    warning("Start discovery failed: %s", e.message);
                }
            }
        }

        public async void stop_discovery() {
            if (adapter != null) {
                try {
                    yield adapter.stop_discovery();
                } catch (Error e) {
                    warning("Stop discovery failed: %s", e.message);
                }
            }
        }

        public async void connect_device(string path) {
            try {
                var device = yield Bus.get_proxy<Device1>(BusType.SYSTEM, "org.bluez", path);
                if (device != null) {
                    yield device.connect();
                }
            } catch (Error e) {
                warning("Connect failed: %s", e.message);
            }
        }

        public async void disconnect_device(string path) {
            try {
                var device = yield Bus.get_proxy<Device1>(BusType.SYSTEM, "org.bluez", path);
                if (device != null) {
                    yield device.disconnect();
                }
            } catch (Error e) {
                warning("Disconnect failed: %s", e.message);
            }
        }

        public async void remove_device(string path) {
            if (adapter != null) {
                try {
                    yield adapter.remove_device(new ObjectPath(path));
                } catch (Error e) {
                    warning("Remove device failed: %s", e.message);
                }
            }
        }
    }
}
