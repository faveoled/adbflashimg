/*
 * adbflashimg - flash an .img file to an Android block device over adb.
 *
 * The image is read in chunks, every chunk is pushed to /tmp/adbflashimg.bin
 * and written to the block device with a 'dd' invocation that skips the chunks
 * that were written before.
 */

using Jadb;

const string TEMP_DIR = "/tmp";
const string DEFAULT_TEMP_FILE = TEMP_DIR + "/adbflashimg.bin";
const string EXIT_MARKER = "ADBFLASHIMG_EXIT";
const int64 DEFAULT_CHUNK_SIZE = 8 * 1024 * 1024;
const int64 USEC_PER_SEC = 1000000;

const int EXIT_SUCCESS = 0;
const int EXIT_FAILURE = 1;
const int EXIT_USAGE = 2;
const int EXIT_INTERRUPTED = 130;

class Options {
    public string? image = null;
    public string? block_device = null;
    public int64 chunk_size = DEFAULT_CHUNK_SIZE;
    public string? serial = null;
    public string adb_host = "localhost";
    public int adb_port = 5037;
    public bool verbose = false;
    public bool keep_temp = false;
    public bool start_server = true;
    public bool check_device = true;
}

/* What BLOCK_DEVICE is on the device. */
enum TargetKind {
    UNKNOWN,
    BLOCK,
    FILE,
    MISSING
}

/* How the dd on the device can be told not to truncate the target. */
enum DdMode {
    CONV_NOTRUNC,
    OFLAG_NOTRUNC,
    SEEK_ONLY
}

bool interrupted = false;

/* SA_RESTART keeps blocking socket reads going, the flag is checked between chunks */
private void on_interrupt_signal (int signal) {
    interrupted = true;
}

private void install_interrupt_handler () {
    /* signal() keeps SA_RESTART on glibc, so blocking socket reads are resumed */
    Posix.signal ((int) Posix.Signal.INT, on_interrupt_signal);
}

private void print_usage () {
    stdout.printf (
"""Usage:
  adbflashimg [OPTION...] IMG BLOCK_DEVICE

Flashes the IMG file to the BLOCK_DEVICE (e.g. /dev/block/by-name/userdata)
of a device connected through adb, in normal or in recovery mode. The file is
read in chunks, every chunk is pushed to %s and written at the right offset
of the block device.

Options:
  -c, --chunk-size=SIZE    chunk size in bytes, accepts a K/M/G suffix (default: %lld)
  -s, --serial=SERIAL      target the device with this serial number
  -H, --adb-host=HOST      adb server host (default: localhost)
  -P, --adb-port=PORT      adb server port (default: 5037)
  -k, --keep-temp          keep %s on the device when finished
  -n, --no-start-server    fail instead of starting the adb server
      --skip-device-check  do not verify that BLOCK_DEVICE exists on the device
  -v, --verbose            print more output
  -h, --help               show this help

Examples:
  adbflashimg boot.img /dev/block/by-name/boot
  adbflashimg --chunk-size=1M system.img /dev/block/sda12
""", DEFAULT_TEMP_FILE, DEFAULT_CHUNK_SIZE, DEFAULT_TEMP_FILE);
}

/* Accepts plain byte counts and K/M/G suffixes, e.g. 512, 8K, 64M, 1G */
private bool parse_size (string text, out int64 size) {
    size = 0;
    string value = text.strip ();
    if (value.length == 0) {
        return false;
    }

    int64 multiplier = 1;
    char last = value[value.length - 1];
    switch (last) {
        case 'k':
        case 'K':
            multiplier = 1024;
            value = value.substring (0, value.length - 1);
            break;
        case 'm':
        case 'M':
            multiplier = 1024 * 1024;
            value = value.substring (0, value.length - 1);
            break;
        case 'g':
        case 'G':
            multiplier = 1024 * 1024 * 1024;
            value = value.substring (0, value.length - 1);
            break;
        default:
            break;
    }

    int64 parsed;
    if (!int64.try_parse (value.strip (), out parsed) || parsed <= 0) {
        return false;
    }
    size = parsed * multiplier;
    return true;
}

private bool needs_value (string[] args, int index, string option) {
    if (index + 1 >= args.length) {
        stderr.printf ("adbflashimg: option '%s' requires an argument\n", option);
        return false;
    }
    return true;
}

private bool parse_options (string[] args, out Options options) {
    options = new Options ();
    var positional = new string[0];

    for (int i = 1; i < args.length; i++) {
        var arg = args[i];
        string name;
        string? inline_value = null;

        if (arg.has_prefix ("--")) {
            var equals = arg.index_of_char ('=');
            if (equals >= 0) {
                name = arg.substring (0, equals);
                inline_value = arg.substring (equals + 1);
            } else {
                name = arg;
            }
        } else if (arg.has_prefix ("-") && arg.length > 1) {
            if (arg.length > 2) {
                name = arg.substring (0, 2);
                inline_value = arg.substring (2);
            } else {
                name = arg;
            }
        } else {
            positional += arg;
            continue;
        }

        bool want_value = false;
        switch (name) {
            case "-c":
            case "--chunk-size":
            case "-s":
            case "--serial":
            case "-H":
            case "--adb-host":
            case "-P":
            case "--adb-port":
                want_value = true;
                break;
            default:
                break;
        }

        string value;
        if (want_value) {
            if (inline_value != null) {
                value = inline_value;
            } else {
                if (!needs_value (args, i, name)) {
                    return false;
                }
                value = args[++i];
            }
        } else if (inline_value != null) {
            stderr.printf ("adbflashimg: option '%s' does not take an argument\n", name);
            return false;
        } else {
            value = "";
        }

        switch (name) {
            case "-c":
            case "--chunk-size":
                if (!parse_size (value, out options.chunk_size)) {
                    stderr.printf ("adbflashimg: invalid chunk size '%s'\n", value);
                    return false;
                }
                break;
            case "-s":
            case "--serial":
                options.serial = value;
                break;
            case "-H":
            case "--adb-host":
                options.adb_host = value;
                break;
            case "-P":
            case "--adb-port":
                int port;
                if (!int.try_parse (value, out port) || port <= 0 || port > 65535) {
                    stderr.printf ("adbflashimg: invalid adb port '%s'\n", value);
                    return false;
                }
                options.adb_port = port;
                break;
            case "-k":
            case "--keep-temp":
                options.keep_temp = true;
                break;
            case "-n":
            case "--no-start-server":
                options.start_server = false;
                break;
            case "--skip-device-check":
                options.check_device = false;
                break;
            case "-v":
            case "--verbose":
                options.verbose = true;
                break;
            case "-h":
            case "--help":
                print_usage ();
                Posix.exit (EXIT_SUCCESS);
                break;
            default:
                stderr.printf ("adbflashimg: unknown option '%s'\ntry 'adbflashimg --help'\n", name);
                return false;
        }
    }

    if (positional.length < 2) {
        stderr.printf ("adbflashimg: expected IMG and BLOCK_DEVICE arguments\ntry 'adbflashimg --help'\n");
        return false;
    }
    if (positional.length > 2) {
        stderr.printf ("adbflashimg: too many arguments\ntry 'adbflashimg --help'\n");
        return false;
    }

    options.image = positional[0];
    options.block_device = positional[1];
    return true;
}

private string format_bytes (int64 bytes) {
    double value = (double) bytes;
    string[] units = { "B", "KiB", "MiB", "GiB", "TiB" };
    int unit = 0;
    while (value >= 1024.0 && unit < units.length - 1) {
        value /= 1024.0;
        unit++;
    }
    if (unit == 0) {
        return "%lld %s".printf (bytes, units[unit]);
    }
    return "%.1f %s".printf (value, units[unit]);
}

private string format_duration (double seconds) {
    int total = (int) seconds;
    return "%02d:%02d:%02d".printf (total / 3600, (total % 3600) / 60, total % 60);
}

private JadbConnection open_connection (Options options) throws JadbException {
    var connection = new JadbConnection (options.adb_host, options.adb_port);

    int64 deadline = GLib.get_monotonic_time () + 10 * USEC_PER_SEC;
    bool launched = false;

    while (true) {
        try {
            var version = connection.get_host_version ();
            if (options.verbose) {
                stdout.printf ("adb server version %s\n", version);
            }
            return connection;
        } catch (JadbException e) {
            if (!options.start_server || launched) {
                throw new JadbException.FAILED ("cannot talk to the adb server at %s:%d (%s)".printf (options.adb_host, options.adb_port, e.message));
            }
            stderr.printf ("adbflashimg: adb server not reachable, starting it...\n");
            try {
                AdbServerLauncher.from_environment (new Jadb.Subprocess ()).launch ();
            } catch (JadbException le) {
                throw new JadbException.FAILED ("failed to start the adb server (%s), is adb installed and in PATH?".printf (le.message));
            }
            launched = true;
            if (GLib.get_monotonic_time () > deadline) {
                throw new JadbException.FAILED ("timed out waiting for the adb server at %s:%d".printf (options.adb_host, options.adb_port));
            }
        }
    }
}

private JadbDevice select_device (Options options, JadbConnection connection) throws JadbException {
    var devices = connection.get_devices ();

    if (options.serial == null) {
        if (devices.length == 0) {
            throw new JadbException.FAILED ("no devices connected to the adb server");
        }
        if (devices.length > 1) {
            var serials = new string[0];
            foreach (var candidate in devices) {
                serials += candidate.get_serial ();
            }
            throw new JadbException.FAILED ("more than one device connected (%s), use --serial".printf (Stream.join (serials, ", ")));
        }
        return devices[0];
    }

    foreach (var candidate in devices) {
        if (candidate.get_serial () == options.serial) {
            return candidate;
        }
    }

    var known = new string[0];
    foreach (var candidate in devices) {
        known += candidate.get_serial ();
    }
    throw new JadbException.FAILED ("device with serial '%s' not found (connected: %s)".printf (options.serial,
        known.length > 0 ? Stream.join (known, ", ") : "none"));
}

private string state_name (JadbDevice.State state) {
    switch (state) {
        case JadbDevice.State.OFFLINE:      return "offline";
        case JadbDevice.State.DEVICE:       return "device";
        case JadbDevice.State.RECOVERY:     return "recovery";
        case JadbDevice.State.BOOTLOADER:   return "bootloader";
        case JadbDevice.State.UNAUTHORIZED: return "unauthorized";
        case JadbDevice.State.AUTHORIZING:  return "authorizing";
        case JadbDevice.State.SIDELOAD:     return "sideload";
        case JadbDevice.State.CONNECTING:   return "connecting";
        case JadbDevice.State.RESCUE:       return "rescue";
        default:                            return "unknown";
    }
}

/* States in which adb shell gives us access to the block devices. */
private bool state_allows_shell (JadbDevice.State state) {
    return state == JadbDevice.State.DEVICE || state == JadbDevice.State.RECOVERY;
}

private void check_device_state (JadbDevice device) throws JadbException {
    var state = device.get_state ();
    if (state_allows_shell (state)) {
        return;
    }
    throw new JadbException.FAILED ("device is in state '%s', expected 'device' or 'recovery'".printf (state_name (state)));
}

/* Asks the device what BLOCK_DEVICE is, so we know if writing to it is safe. */
private TargetKind check_target (JadbDevice device, string block_device) throws JadbException {
    var quoted = Bash.quote (block_device);
    var output = run_command_line (device,
        "if [ -b %s ]; then echo block; elif [ -e %s ]; then echo file; else echo missing; fi"
        .printf (quoted, quoted));
    switch (output.strip ()) {
        case "block":   return TargetKind.BLOCK;
        case "file":    return TargetKind.FILE;
        case "missing": return TargetKind.MISSING;
        default:        return TargetKind.UNKNOWN;
    }
}

/*
 * Some Android builds ship a dd without conv support ("dd: conv option disabled"),
 * so find out once which way it can be told to keep the rest of the target.
 * The probe writes to /dev/null, it never touches the real target.
 */
private DdMode detect_dd_mode (JadbDevice device) throws JadbException {
    string[] options = { " conv=notrunc", " oflag=notrunc", "" };
    for (int i = 0; i < options.length; i++) {
        var output = run_command_line (device,
            "dd if=/dev/null of=/dev/null bs=1 count=0%s 2>&1; echo %s:$?"
            .printf (options[i], EXIT_MARKER));
        string body;
        if ((int) extract_exit_code (output, out body) == 0) {
            switch (i) {
                case 0:  return DdMode.CONV_NOTRUNC;
                case 1:  return DdMode.OFLAG_NOTRUNC;
                default: return DdMode.SEEK_ONLY;
            }
        }
    }
    return DdMode.SEEK_ONLY;
}

private string dd_mode_name (DdMode mode) {
    switch (mode) {
        case DdMode.CONV_NOTRUNC: return "conv=notrunc";
        case DdMode.OFLAG_NOTRUNC: return "oflag=notrunc";
        default:                  return "seek only";
    }
}

/*
 * dd skips seek records of size bs before writing, so chunk n lands at n * chunk_size.
 * Without conv/oflag notrunc dd opens the target with O_TRUNC, which the kernel ignores
 * for block devices, so plain seek is still safe there.
 */
private string dd_command_line (string block_device, int64 chunk_size, int64 index, DdMode mode) {
    string option = "";
    switch (mode) {
        case DdMode.CONV_NOTRUNC: option = " conv=notrunc"; break;
        case DdMode.OFLAG_NOTRUNC: option = " oflag=notrunc"; break;
        default: break;
    }
    return "dd if=%s of=%s bs=%lld seek=%lld%s 2>&1".printf (
        Bash.quote (DEFAULT_TEMP_FILE), Bash.quote (block_device), chunk_size, index, option);
}

/*
 * Looks for the exit status marker appended to a shell command and returns it,
 * the marker is removed from the given body.
 */
private int64 extract_exit_code (string output, out string body) {
    body = output;
    var lines = output.split ("\n");
    for (int i = lines.length - 1; i >= 0; i--) {
        var line = lines[i].strip ();
        if (line.has_prefix (EXIT_MARKER + ":")) {
            int64 parsed;
            body = Stream.join (lines[0:i], "\n");
            if (int64.try_parse (line.substring (EXIT_MARKER.length + 1).strip (), out parsed)) {
                return parsed;
            }
            return -1;
        }
    }
    return -1;
}

/* Reads a command output stream until the command is done and closes it. */
private string read_stream (GLib.InputStream stream) throws JadbException {
    var output = Stream.read_all (stream);
    try {
        stream.close ();
    } catch (GLib.IOError e) {
        /* the transport is gone anyway */
    }
    return output;
}

/* Runs a command with arguments on the device and returns its combined output. */
private string run_command (JadbDevice device, string command, string[] args = new string[0]) throws JadbException {
    return read_stream (device.execute_shell (command, args));
}

/* Runs a command line on the device and throws when it reports a failure. */
private string run_command_checked (JadbDevice device, string command_line) throws JadbException {
    var output = run_command_line (device, "%s; echo %s:$?".printf (command_line, EXIT_MARKER));

    string body;
    int exit_code = (int) extract_exit_code (output, out body);
    if (exit_code != 0) {
        throw new JadbException.FAILED ("command '%s' failed with exit code %d: %s".printf (
            command_line, exit_code, body.strip ()));
    }
    return body;
}

/* Runs a complete command line on the device and returns its combined output. */
private string run_command_line (JadbDevice device, string command_line) throws JadbException {
    return read_stream (device.execute_shell_line (command_line));
}

private bool is_tty () {
    return Posix.isatty (1);
}

private void cleanup_temp_file (JadbDevice device, Options options) {
    if (options.keep_temp) {
        return;
    }
    try {
        run_command (device, "rm", new string[] { "-f", DEFAULT_TEMP_FILE });
    } catch (JadbException e) {
        stderr.printf ("adbflashimg: warning: could not remove %s: %s\n", DEFAULT_TEMP_FILE, e.message);
    }
}

int main (string[] args) {
    Options options;
    if (!parse_options (args, out options)) {
        return EXIT_USAGE;
    }

    var image_file = GLib.File.new_for_path (options.image);
    JadbDevice? device = null;
    TargetKind target = TargetKind.UNKNOWN;
    DdMode dd_mode = DdMode.CONV_NOTRUNC;
    int64 image_size;

    try {
        if (!image_file.query_exists ()) {
            throw new JadbException.FAILED ("no such file: %s".printf (options.image));
        }
        var info = image_file.query_info ("standard::size,standard::type",
                                          GLib.FileQueryInfoFlags.NONE, null);
        image_size = info.get_size ();
        if (info.get_file_type () != GLib.FileType.REGULAR) {
            throw new JadbException.FAILED ("%s is not a regular file".printf (options.image));
        }

        if (image_size == 0) {
            throw new JadbException.FAILED ("%s is empty".printf (options.image));
        }
        /* an image larger than one chunk is the normal case, only the last chunk is shorter */

        var connection = open_connection (options);
        device = select_device (options, connection);
        check_device_state (device);

        stdout.printf ("adbflashimg: %s -> %s (%s, %s), chunk size %s\n",
                       options.image, options.block_device,
                       device.get_serial () ?? "any device", state_name (device.get_state ()),
                       format_bytes (options.chunk_size));

        if (options.check_device) {
            target = check_target (device, options.block_device);
            if (target == TargetKind.MISSING) {
                throw new JadbException.FAILED ("%s does not exist on the device".printf (options.block_device));
            }
        }

        /* the recovery ramdisk does not always have the temporary directory yet */
        run_command_line (device, "mkdir -p %s".printf (Bash.quote (TEMP_DIR)));

        dd_mode = detect_dd_mode (device);
        if (options.verbose) {
            stdout.printf ("adbflashimg: writing with dd (%s)\n", dd_mode_name (dd_mode));
        }
        if (dd_mode == DdMode.SEEK_ONLY && target == TargetKind.FILE) {
            throw new JadbException.FAILED (
                "the dd on the device supports neither conv=notrunc nor oflag=notrunc, " +
                "writing to %s would truncate it; only block devices are safe here"
                .printf (options.block_device));
        }

        install_interrupt_handler ();
    } catch (JadbException e) {
        stderr.printf ("adbflashimg: error: %s\n", e.message);
        return EXIT_FAILURE;
    } catch (GLib.Error e) {
        stderr.printf ("adbflashimg: error: %s\n", e.message);
        return EXIT_FAILURE;
    }

    int result = EXIT_SUCCESS;
    var remote_file = new RemoteFile (DEFAULT_TEMP_FILE);
    var tty = is_tty ();
    int64 written = 0;
    int64 index = 0;
    int64 chunk_count = (image_size + options.chunk_size - 1) / options.chunk_size;
    int64 started_at = GLib.get_monotonic_time ();

    try {
        var stream = image_file.read ();
        while (true) {
            if (interrupted) {
                throw new JadbException.FAILED ("interrupted after %lld bytes".printf (written));
            }

            var bytes = stream.read_bytes ((size_t) options.chunk_size, null);
            var chunk = bytes.get_data ();
            if (chunk.length == 0) {
                break;
            }

            device.push_data (chunk, GLib.get_real_time () / USEC_PER_SEC, 0664, remote_file);
            written += chunk.length;

            /* dd skips the chunks that are already on the device and writes this one in place */
            var dd_output = run_command_checked (device,
                dd_command_line (options.block_device, options.chunk_size, index, dd_mode));
            if (options.verbose && dd_output.strip () != "") {
                stdout.printf ("chunk %lld: %s\n", index, dd_output.strip ());
            }

            index++;

            double elapsed = (double) (GLib.get_monotonic_time () - started_at) / (double) USEC_PER_SEC;
            double speed = elapsed > 0 ? (double) written / elapsed : 0;
            double eta = speed > 0 ? (double) (image_size - written) / speed : 0;
            if (tty) {
                stdout.printf ("\r[%3d%%] %s / %s  %s/s  ETA %s", (int) (100.0 * index / (double) chunk_count),
                               format_bytes (written), format_bytes (image_size),
                               format_bytes ((int64) speed), format_duration (eta));
                stdout.flush ();
            } else if (index == chunk_count || index % 10 == 0) {
                stdout.printf ("[%3d%%] %s / %s\n", (int) (100.0 * index / (double) chunk_count),
                               format_bytes (written), format_bytes (image_size));
            }
        }
        stream.close ();

        /* flush the device buffers before reporting success */
        run_command (device, "sync");

        if (written < image_size) {
            throw new JadbException.FAILED ("only %lld of %lld bytes were sent".printf (written, image_size));
        }
        if (tty) {
            stdout.printf ("\n");
        }
        stdout.printf ("adbflashimg: done, %s written to %s\n", format_bytes (written), options.block_device);
    } catch (JadbException e) {
        if (tty) {
            stdout.printf ("\n");
        }
        if (interrupted) {
            stderr.printf ("adbflashimg: interrupted: %s\n", e.message);
            result = EXIT_INTERRUPTED;
        } else {
            stderr.printf ("adbflashimg: error: %s\n", e.message);
            result = EXIT_FAILURE;
        }
    } catch (GLib.Error e) {
        if (tty) {
            stdout.printf ("\n");
        }
        stderr.printf ("adbflashimg: error: %s\n", e.message);
        result = EXIT_FAILURE;
    } finally {
        cleanup_temp_file (device, options);
    }

    return result;
}