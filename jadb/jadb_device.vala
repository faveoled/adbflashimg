/*
 * Port of jadb (https://github.com/vidstige/jadb) to Vala.
 * Original file: src/se/vidstige/jadb/JadbDevice.java
 *
 * Only the parts needed by adbflashimg (device selection, state, push, shell) are ported.
 */

namespace Jadb {
    public class JadbDevice : GLib.Object {
        public enum State {
            UNKNOWN,
            OFFLINE,
            DEVICE,
            RECOVERY,
            BOOTLOADER,
            UNAUTHORIZED,
            AUTHORIZING,
            SIDELOAD,
            CONNECTING,
            RESCUE
        }

        /* noinspection OctalInteger */
        private const int DEFAULT_MODE = 0664;

        private string? serial;
        private JadbConnection connection;

        public JadbDevice (string? serial, JadbConnection connection) {
            this.serial = serial;
            this.connection = connection;
        }

        public static JadbDevice create_any (JadbConnection connection) {
            return new JadbDevice (null, connection);
        }

        private State convert_state (string type) {
            switch (type) {
                case "device":       return State.DEVICE;
                case "offline":      return State.OFFLINE;
                case "bootloader":   return State.BOOTLOADER;
                case "recovery":     return State.RECOVERY;
                case "unauthorized": return State.UNAUTHORIZED;
                case "authorizing":  return State.AUTHORIZING;
                case "connecting":   return State.CONNECTING;
                case "sideload":     return State.SIDELOAD;
                case "rescue":       return State.RESCUE;
                default:             return State.UNKNOWN;
            }
        }

        private Transport get_transport () throws JadbException {
            var transport = connection.create_transport ();
            /* Do not close the transport here, the caller owns it. */
            try {
                send (transport, serial == null ? "host:transport-any" : "host:transport:" + serial);
            } catch (JadbException e) {
                transport.close ();
                throw e;
            }
            return transport;
        }

        public string? get_serial () {
            return serial;
        }

        public State get_state () throws JadbException {
            var transport = connection.create_transport ();
            send (transport, serial == null ? "host:get-state" : "host-serial:" + serial + ":get-state");
            var state = convert_state (transport.read_string ());
            transport.close ();
            return state;
        }

        /*
         * <p>Execute a shell command.</p>
         *
         * <p>The returned stream combines stdout and stderr, the caller has to close it.</p>
         *
         * @param command main command to run. E.g. "ls"
         * @param args arguments to the command.
         */
        public GLib.InputStream execute_shell (string command, string[] args = new string[0]) throws JadbException {
            var transport = get_transport ();
            var shell_line = build_cmd_line (command, args);
            send (transport, "shell:" + shell_line);
            return new AdbFilterInputStream (transport.input_stream, transport.socket, transport);
        }

        /* Runs a complete command line as given, without any quoting applied by us. */
        public GLib.InputStream execute_shell_line (string shell_line) throws JadbException {
            var transport = get_transport ();
            send (transport, "shell:" + shell_line);
            return new AdbFilterInputStream (transport.input_stream, transport.socket, transport);
        }

        /*
         * Builds a command line string from the command and its arguments.
         *
         * @param command the command.
         * @param args the list of arguments.
         * @return the command line.
         */
        private string build_cmd_line (string command, string[] args) {
            var shell_line = new GLib.StringBuilder (command);
            foreach (var arg in args) {
                shell_line.append_c (' ');
                shell_line.append (Bash.quote (arg));
            }
            return shell_line.str;
        }

        /*
         * <p>Pushes a stream to the device.</p>
         *
         * @param source the data to send.
         * @param last_modified modification time in seconds since the epoch.
         * @param mode file mode, e.g. 0664.
         * @param remote destination on the device.
         */
        public void push (GLib.InputStream source, int64 last_modified, int mode, RemoteFile remote) throws JadbException {
            var transport = get_transport ();
            try {
                var sync = transport.start_sync ();
                sync.send ("SEND", remote.get_path () + "," + mode.to_string ());

                sync.send_stream (source);

                sync.send_status ("DONE", (int) last_modified);
                sync.verify_status ();
            } finally {
                transport.close ();
            }
        }

        /* Convenience overload pushing an in memory buffer. */
        public void push_data (uint8[] data, int64 last_modified, int mode, RemoteFile remote) throws JadbException {
            var transport = get_transport ();
            try {
                var sync = transport.start_sync ();
                sync.send ("SEND", remote.get_path () + "," + mode.to_string ());

                sync.send_data (data);

                sync.send_status ("DONE", (int) last_modified);
                sync.verify_status ();
            } finally {
                transport.close ();
            }
        }

        private void send (Transport transport, string command) throws JadbException {
            transport.send (command);
            transport.verify_response ();
        }
    }
}