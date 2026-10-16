/*
 * Port of jadb (https://github.com/vidstige/jadb) to Vala.
 * Original files: src/se/vidstige/jadb/AdbServerLauncher.java,
 *                 src/se/vidstige/jadb/Subprocess.java
 */

namespace Jadb {
    /* Original file: src/se/vidstige/jadb/Subprocess.java */
    public class Subprocess : GLib.Object {
        public int execute (string[] command) throws JadbException {
            string standard_output;
            string standard_error;
            int wait_status;
            try {
                GLib.Process.spawn_sync (null, command, null, GLib.SpawnFlags.SEARCH_PATH, null,
                                          out standard_output, out standard_error, out wait_status);
            } catch (GLib.SpawnError e) {
                throw new JadbException.FAILED ("failed to run '%s': %s".printf (Stream.join (command, " "), e.message));
            }
            if (wait_status != 0) {
                throw new JadbException.FAILED ("'%s' exited with status %d: %s".printf (Stream.join (command, " "), wait_status, standard_error.strip ()));
            }
            return wait_status;
        }
    }

    /*
     * Launches the ADB server
     */
    public class AdbServerLauncher : GLib.Object {
        private string executable;
        private Subprocess subprocess;

        /*
         * Creates a new launcher with the specified ADB.
         *
         * @param subprocess the sub-process.
         * @param executable the location of the ADB executable.
         */
        public AdbServerLauncher (Subprocess subprocess, string executable) {
            this.subprocess = subprocess;
            this.executable = executable;
        }

        /* Creates a new launcher loading ADB from the environment. */
        public static AdbServerLauncher from_environment (Subprocess subprocess) {
            return new AdbServerLauncher (subprocess, find_adb_executable ());
        }

        private static string find_adb_executable () {
            string? android_home = GLib.Environment.get_variable ("ANDROID_HOME");
            if (android_home == null || android_home == "") {
                return "adb";
            }
            return android_home + "/platform-tools/adb";
        }

        public void launch () throws JadbException {
            int exit_value = subprocess.execute (new string[] { executable, "start-server" });
            if (exit_value != 0) {
                throw new JadbException.FAILED ("adb exited with exit code: " + exit_value.to_string ());
            }
        }
    }
}