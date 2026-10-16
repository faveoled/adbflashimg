/*
 * Port of jadb (https://github.com/vidstige/jadb) to Vala.
 * Original file: src/se/vidstige/jadb/SyncTransport.java
 *
 * Only the parts needed by adbflashimg (pushing files) are ported.
 */

namespace Jadb {
    public class SyncTransport : GLib.Object {
        private const int CHUNK_SIZE = 1024 * 64;

        private GLib.OutputStream output;
        private GLib.InputStream input;

        public SyncTransport (GLib.OutputStream output_stream, GLib.InputStream input_stream) {
            this.output = output_stream;
            this.input = input_stream;
        }

        public void send (string sync_command, string name) throws JadbException {
            if (sync_command.length != 4) {
                throw new JadbException.FAILED ("sync commands must have length 4");
            }
            Stream.write_fully (output, sync_command.data);
            var data = name.data;
            write_int (data.length);
            Stream.write_fully (output, data);
        }

        public void send_status (string status_code, int length) throws JadbException {
            Stream.write_fully (output, status_code.data);
            write_int (length);
        }

        public void verify_status () throws JadbException {
            var status = read_string (4);
            int length = read_int ();
            if (status == "FAIL") {
                var error = read_string (length);
                throw new JadbException.FAILED (error);
            }
            if (status != "OKAY") {
                throw new JadbException.FAILED ("Unknown error: " + status);
            }
        }

        private void write_int (int value) throws JadbException {
            var data = new uint8[4];
            data[0] = (uint8) (value & 0xff);
            data[1] = (uint8) ((value >> 8) & 0xff);
            data[2] = (uint8) ((value >> 16) & 0xff);
            data[3] = (uint8) ((value >> 24) & 0xff);
            Stream.write_fully (output, data);
        }

        private int read_int () throws JadbException {
            var data = new uint8[4];
            Stream.read_fully (input, data);
            /* the sync protocol uses little endian integers */
            return data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
        }

        private string read_string (int length) throws JadbException {
            var buffer = new uint8[length];
            Stream.read_fully (input, buffer);
            return Stream.to_string (buffer);
        }

        private void send_chunk (uint8[] buffer, int offset, int length) throws JadbException {
            Stream.write_fully (output, "DATA".data);
            write_int (length);
            var payload = new uint8[length];
            GLib.Memory.move (&payload[0], &buffer[offset], (size_t) length);
            Stream.write_fully (output, payload);
        }

        public void send_stream (GLib.InputStream source) throws JadbException {
            var buffer = new uint8[CHUNK_SIZE];
            ssize_t n = Stream.read (source, buffer);
            while (n > 0) {
                send_chunk (buffer, 0, (int) n);
                n = Stream.read (source, buffer);
            }
        }

        public void send_data (uint8[] data) throws JadbException {
            size_t offset = 0;
            while (offset < data.length) {
                var remaining = data.length - offset;
                var chunk = new uint8[remaining < CHUNK_SIZE ? remaining : CHUNK_SIZE];
                GLib.Memory.move (&chunk[0], &data[offset], chunk.length);
                send_chunk (chunk, 0, (int) chunk.length);
                offset += chunk.length;
            }
        }

    }
}