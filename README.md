# adbflashimg
Flash .img files from PC over adb

```
$ adbflashimg --help
Usage: adbflashimg [OPTIONS] <src-img.img> <block-device>
Example: adbflashimg system.img /dev/block/system"
adbflashimg is a CLI utility for flashing .img files over adb.
Options:

      --adb-device  <arg>      Identifier of adb device (required if you have >1
                               adb devices).
      --chunk-size  <arg>      Max size of chunk travelling over USB (bytes).
                               Default: 50331648 (48MiB).
      --dd-block-size  <arg>   dd chunk size for writing to device storage.
                               Default: 4194304 (4MiB).
      --debug                  Enables debugging mode if specified. Prints out
                               more logs.
      --skip  <arg>            How many chunks to skip. Useful in case of
                               partial failures. Default: 0.
  -h, --help                   Show help message

 trailing arguments:
  src-img (required)        Source .img file to be flashed.
  block-device (required)   Block device for .img to be flashed to (located at
                            /dev/block/).
```
