# TUI Disk Info in POSIX awk

Inspired by [otakuto/crazydiskinfo](https://github.com/otakuto/crazydiskinfo).
This script improves on it by using smartmontools for data and simply
displaying that information in a style similar to
[CrystalDiskInfo](https://crystalmark.info/en/software/crystaldiskinfo/).

The script was tested on:

- mawk
- GNU Awk
- busybox awk
- One True AWK

The list is sorted by execution speed.
