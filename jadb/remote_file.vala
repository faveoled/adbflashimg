/*
 * Port of jadb (https://github.com/vidstige/jadb) to Vala.
 * Original file: src/se/vidstige/jadb/RemoteFile.java
 */

namespace Jadb {
    public class RemoteFile : GLib.Object {
        private string path;

        public RemoteFile (string path) {
            this.path = path;
        }

        public string get_path () {
            return path;
        }
    }
}