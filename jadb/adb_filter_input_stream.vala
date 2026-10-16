/*
 * Port of jadb (https://github.com/vidstige/jadb) to Vala.
 * Original file: src/se/vidstige/jadb/AdbFilterInputStream.java
 */

namespace Jadb {
    /*
     * adb shell turns LF into CRLF on some devices, this filters the CR back out,
     * mirroring jadb's AdbFilterInputStream. Unlike a plain buffered reader it returns
     * as soon as no more data is available, which keeps interactive commands working.
     */
    public class AdbFilterInputStream : GLib.InputStream {
        private GLib.InputStream inner;
        private GLib.Socket? socket;
        /* the transport owning the streams must stay alive while we read from them */
        private GLib.Object? owner;
        private bool pushback_available = false;
        private uint8 pushback_byte;

        public AdbFilterInputStream (GLib.InputStream inner, GLib.Socket? socket = null, GLib.Object? owner = null) {
            this.inner = inner;
            this.socket = socket;
            this.owner = owner;
        }

        /* Raw single byte read with one byte of pushback, replaces mark()/reset() in Java */
        private int read_raw_byte () throws GLib.IOError {
            if (pushback_available) {
                pushback_available = false;
                return pushback_byte;
            }
            var buffer = new uint8[1];
            ssize_t n = inner.read (buffer);
            return n > 0 ? buffer[0] : -1;
        }

        private void push_back (int b) {
            pushback_byte = (uint8) b;
            pushback_available = true;
        }

        private int read_byte () throws GLib.IOError {
            int b1 = read_raw_byte ();
            if (b1 == 0x0d) {
                int b2 = read_raw_byte ();
                if (b2 == 0x0a) {
                    return b2;
                }
                if (b2 != -1) {
                    push_back (b2);
                }
            }
            return b1;
        }

        public override ssize_t read (uint8[] buffer, GLib.Cancellable? cancellable = null) throws GLib.IOError {
            int n = 0;
            for (int i = 0; i < buffer.length; i++) {
                int b = read_byte ();
                if (b == -1) {
                    return n == 0 ? -1 : n;
                }
                buffer[n] = (uint8) b;
                n++;

                /* Return as soon as no more data is available (and at least one byte was read) */
                if (socket != null && socket.get_available_bytes () <= 0) {
                    return n;
                }
            }
            return n;
        }

        public override bool close (GLib.Cancellable? cancellable = null) throws GLib.IOError {
            return inner.close (cancellable);
        }
    }
}