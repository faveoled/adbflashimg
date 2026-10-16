/*
 * Port of jadb (https://github.com/vidstige/jadb) to Vala.
 * Original file: src/se/vidstige/jadb/JadbConnection.java
 */

namespace Jadb {
    public class JadbConnection : GLib.Object {
        private const int DEFAULT_PORT = 5037;

        private string host;
        private int port;

        public static JadbConnection create_default () {
            return new JadbConnection ("localhost", DEFAULT_PORT);
        }

        public JadbConnection (string host, int port) {
            this.host = host;
            this.port = port;
        }

        public Transport create_transport () throws JadbException {
            return Transport.create_socket (host, port);
        }

        public string get_host_version () throws JadbException {
            var transport = create_transport ();
            transport.send ("host:version");
            transport.verify_response ();
            var version = transport.read_string ();
            transport.close ();
            return version;
        }

        public JadbDevice[] get_devices () throws JadbException {
            var transport = create_transport ();
            transport.send ("host:devices");
            transport.verify_response ();
            var body = transport.read_string ();
            transport.close ();
            return parse_devices (body);
        }

        public JadbDevice[] parse_devices (string body) {
            var devices = new JadbDevice[0];
            foreach (var line in body.split ("\n")) {
                var parts = line.split ("\t");
                if (parts.length > 1) {
                    devices += new JadbDevice (parts[0], this); /* parts[1] is type */
                }
            }
            return devices;
        }

        public JadbDevice get_any_device () {
            return JadbDevice.create_any (this);
        }
    }
}