# Clonezilla Altiris Imaging

<p align="center">
  <img src=".github/logo.png" alt="clonezilla-altiris-imaging logo" width="128" />
</p>

A Perl script that drives Clonezilla disk imaging using machine settings
from an Altiris deployment server.

## What it does

`main.pl`:

1. Looks up the machine's configuration on the Altiris server by MAC
   address.
2. Mounts the image share on `/home/partimag`.
3. Checks the requested partitions against the disks it finds and asks
   for confirmation.
4. Backs up partitions with `ocs-sr saveparts` or restores them with
   `ocs-sr restoreparts`.

If anything goes wrong it drops you to the console.

## Tech

- Perl
- Clonezilla (`ocs-sr`) and Altiris

## Usage

Run `main.pl` from a Clonezilla live environment that can reach the
Altiris server and the image share.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).
