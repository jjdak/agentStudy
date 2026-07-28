# Third-party notices

This Lab downloads a fixed snapshot of [curl](https://github.com/curl/curl)
and a fixed upstream patch during trusted environment preparation. curl is
distributed under the curl license; a copy is stored in
[`licenses/curl-LICENSE`](licenses/curl-LICENSE).

The toolchain image is based on the official Debian `bookworm-slim` image and
installs Debian packages during preparation. The exact installed package list
and resulting toolchain ID are recorded under `.runtime/`; export the offline
bundle to preserve that prepared environment.

The portable bundle redistributes the extracted Debian package files, including
Bubblewrap. Debian package copyright and license files remain inside the
rootfs under `/usr/share/doc/*/copyright` and must be preserved with the
bundle. Bubblewrap is maintained at
[containers/bubblewrap](https://github.com/containers/bubblewrap).
