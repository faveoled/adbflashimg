/*
 * Port of jadb (https://github.com/vidstige/jadb) to Vala.
 * Original files: src/se/vidstige/jadb/Stream.java,
 *                 src/se/vidstige/jadb/managers/Bash.java
 */

namespace Jadb {
    /* Original file: src/se/vidstige/jadb/Stream.java */
    public class Stream {
        private Stream () {
        }

        public static string read_all (GLib.InputStream input) throws JadbException {
            var accumulator = new GLib.ByteArray ();
            var buffer = new uint8[1024 * 10];
            while (true) {
                ssize_t len = read (input, buffer);
                if (len < 0) {
                    break;
                }
                if (len == 0) {
                    continue;
                }
                accumulator.append (buffer[0:len]);
            }
            return to_string (accumulator.data);
        }

        /*
         * Converts received bytes to a string. The data read from adb is not null terminated,
         * so it must not be cast to a string directly, that would scan past the end of the buffer.
         */
        public static string to_string (uint8[] data) {
            var builder = new GLib.StringBuilder.sized (data.length);
            for (int i = 0; i < data.length; i++) {
                builder.append_c ((char) data[i]);
            }
            return builder.str;
        }

        /*
         * Joins values with a separator. string.join with a string array is broken with
         * valac 0.56 (it generates a call to the variadic g_strjoinv), so do it by hand.
         */
        public static string join (string[] values, string separator) {
            var builder = new GLib.StringBuilder ();
            for (int i = 0; i < values.length; i++) {
                if (i > 0) {
                    builder.append_c (separator[0]);
                }
                builder.append (values[i]);
            }
            return builder.str;
        }

        /* Reads into the front of buffer, returns the number of bytes read or -1 on EOF. */
        public static ssize_t read (GLib.InputStream input, uint8[] buffer) {
            try {
                return input.read (buffer);
            } catch (GLib.IOError e) {
                return -1;
            }
        }

        /* Reads exactly buffer.length bytes, throws when the stream ends prematurely. */
        public static void read_fully (GLib.InputStream input, uint8[] buffer) throws JadbException {
            int total = 0;
            while (total < buffer.length) {
                var rest = new uint8[buffer.length - total];
                ssize_t n = read (input, rest);
                if (n <= 0) {
                    throw new JadbException.FAILED ("unexpected end of stream, wanted %u bytes, got %u".printf (buffer.length, total));
                }
                GLib.Memory.move (&buffer[total], &rest[0], (size_t) n);
                total += (int) n;
            }
        }

        /*
         * Writes a buffer completely, GIO streams may accept less than asked for.
         * Vala has no pointer arithmetic on arrays, so a short write is retried with a copy
         * of the remaining bytes, which is fine for the sizes used by the adb protocol.
         */
        public static void write_fully (GLib.OutputStream output, uint8[] buffer) throws JadbException {
            int total = 0;
            while (total < buffer.length) {
                var rest = new uint8[buffer.length - total];
                GLib.Memory.move (&rest[0], &buffer[total], (size_t) (buffer.length - total));
                ssize_t n;
                try {
                    n = output.write (rest);
                } catch (GLib.IOError e) {
                    throw new JadbException.FAILED ("failed to write stream: " + e.message);
                }
                if (n < 0) {
                    throw new JadbException.FAILED ("failed to write to stream");
                }
                total += (int) n;
            }
        }
    }

    /* Original file: src/se/vidstige/jadb/managers/Bash.java */
    public class Bash {
        private Bash () {
        }

        public static string quote (string s) {
            return "'" + s.replace ("'", "'\\''") + "'";
        }
    }
}