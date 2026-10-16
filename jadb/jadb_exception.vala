/*
 * Port of jadb (https://github.com/vidstige/jadb) to Vala.
 * Original file: src/se/vidstige/jadb/JadbException.java
 */

namespace Jadb {
    public errordomain JadbException {
        /* every jadb failure maps to this single code */
        FAILED;
    }
}