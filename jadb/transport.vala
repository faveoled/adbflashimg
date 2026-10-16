/*
 * Port of jadb (https://github.com/vidstige/jadb) to Vala.
 * Original file: src/se/vidstige/jadb/Transport.java
 */

namespace Jadb {
    public class Transport : GLib.Object {
        public GLib.InputStream input_stream { get; private set; }
        public GLib.OutputStream output_stream { get; private set; }
        /* kept to be able to ask how much data is already buffered, used by AdbFilterInputStream */
        public GLib.Socket? socket { get; private set; }
        /* the streams belong to the socket connection, so it has to be kept alive */
        private GLib.Object? owner;

        public Transport (GLib.InputStream input_stream, GLib.OutputStream output_stream,
                          GLib.Socket? socket = null, GLib.Object? owner = null) {
            this.input_stream = input_stream;
            this.output_stream = output_stream;
            this.socket = socket;
            this.owner = owner;
        }

        /* jadb opens a plain TCP socket to the adb server */
        public static Transport create_socket (string host, int port) throws JadbException {
            try {
                var client = new GLib.SocketClient ();
                client.timeout = 10;
                var connection = client.connect_to_host (host, (uint16) port);
                return new Transport (connection.input_stream, connection.output_stream,
                                      connection.socket, connection);
            } catch (GLib.Error e) {
                throw new JadbException.FAILED ("failed to connect to adb server at %s:%d (%s)".printf (host, port, e.message));
            }
        }

        public string read_string () throws JadbException {
            int length;
            if (!int.try_parse (read_string_n (4), out length, null, 16)) {
                throw new JadbException.FAILED ("invalid response length from adb server");
            }
            return read_string_n (length);
        }

        public string read_string_n (int length) throws JadbException {
            var response_buffer = new uint8[length];
            Stream.read_fully (input_stream, response_buffer);
            return Stream.to_string (response_buffer);
        }

        public void verify_response () throws JadbException {
            var response = read_string_n (4);
            if (response != "OKAY") {
                var error = read_string ();
                throw new JadbException.FAILED ("command failed: " + error);
            }
        }

        private string get_command_length (string command) {
            return "%04x".printf (command.data.length);
        }

        public void send (string command) throws JadbException {
            Stream.write_fully (output_stream, get_command_length (command).data);
            Stream.write_fully (output_stream, command.data);
        }

        public SyncTransport start_sync () throws JadbException {
            send ("sync:");
            verify_response ();
            return new SyncTransport (output_stream, input_stream);
        }

        public void close () {
            try {
                input_stream.close ();
            } catch (GLib.IOError e) {
            }
            try {
                output_stream.close ();
            } catch (GLib.IOError e) {
            }
        }
    }
}