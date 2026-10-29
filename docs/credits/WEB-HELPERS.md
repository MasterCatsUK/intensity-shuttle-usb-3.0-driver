# Shuttle Player web-helper credits

Part of the [project credits](../../CREDITS.md). Thank you to the authors and maintainers of yt-dlp and its upstream dependencies.

Shuttle Player 0.3.2 uses the pinned official `yt-dlp_macos` 2026.10.26 executable, plus separate QuickJS 2026-06-04 and LGPL-configured FFmpeg 8.1.3 helpers. See [Player third-party notices](../../player/THIRD-PARTY-NOTICES.md), [pinned source inputs](../../player/vendor/web-tools/) and [build recipes](../../player/tools/build_web_tools.sh).

## Upstream yt-dlp notice catalogue

The index below is transcribed from every component heading in the retained upstream [full third-party notice](../../player/resources/Web-Licences/yt-dlp-THIRD-PARTY.txt). That catalogue covers multiple upstream build/platform variants; it is **not** a claim that every component is present or used in the macOS executable. The complete notice contains the actual copyright holders, full terms, exceptions and source references. Preserve it with the executable; this index does not replace it or relicense any dependency.

| Component / upstream authors | Licence label in upstream notice | Upstream reference |
|---|---|---|
| Python | PSF-2.0 | [Project](https://www.python.org/) |
| bzip2 | bzip2-1.0.6 | [Project](https://sourceware.org/bzip2/) |
| libffi | MIT | [Project](https://sourceware.org/libffi/) |
| OpenSSL 1.x | OpenSSL | [Project](https://www.openssl.org/) |
| OpenSSL 3.0+ | Apache-2.0 | [Project](https://www.openssl.org/) |
| SQLite | Public Domain | [Project](https://www.sqlite.org/) |
| liblzma | 0BSD | [Project](https://tukaani.org/xz/) |
| mpdecimal | BSD-2-Clause | [Project](https://www.bytereef.org/mpdecimal/) |
| zlib | zlib | [Project](https://zlib.net/) |
| Expat | MIT | [Project](https://libexpat.github.io/) |
| ncurses | X11-distribute-modifications-variant | [Project](https://invisible-island.net/ncurses/) |
| GNU Readline | GPL-3.0-or-later | [Project](https://www.gnu.org/software/readline/) |
| libstdc++ | GPL-3.0-with-GCC-exception | [Project](https://gcc.gnu.org/onlinedocs/libstdc++/) |
| libgcc | GPL-3.0-with-GCC-exception | [Project](https://gcc.gnu.org/) |
| libuuid | BSD-3-Clause | [Project](https://git.kernel.org/pub/scm/fs/ext2/e2fsprogs.git/tree/lib/uuid) |
| libintl | LGPL-2.1-or-later | [Project](https://www.gnu.org/software/gettext/) |
| libidn2 | LGPL-3.0-or-later | [Project](https://www.gnu.org/software/libidn/) |
| libidn2 (Unicode character data files) | Unicode-TOU AND Unicode-DFS-2016 | [Project](https://www.gnu.org/software/libidn/) |
| libunistring | LGPL-3.0-or-later | [Project](https://www.gnu.org/software/libunistring/) |
| curl-impersonate | MIT | [Project](https://github.com/lexiforest/curl-impersonate) |
| curl | curl | [Project](https://curl.se/) |
| BoringSSL | Apache-2.0 | [Project](https://boringssl.googlesource.com/boringssl) |
| nghttp2 | MIT | [Project](https://nghttp2.org/) |
| ngtcp2 | MIT | [Project](https://nghttp2.org/ngtcp2/) |
| nghttp3 | MIT | [Project](https://nghttp2.org/nghttp3/) |
| zstd | BSD-3-Clause | [Project](https://facebook.github.io/zstd/) |
| brotli | MIT | [Project](https://brotli.org/) |
| curl_cffi | MIT | [Project](https://curl-cffi.readthedocs.io/) |
| Tornado | Apache-2.0 | [Project](http://www.tornadoweb.org/) |
| httpx | BSD-3-Clause | [Project](https://www.python-httpx.org/) |
| cffi | MIT-0 | [Project](https://cffi.readthedocs.io/) |
| pycparser | BSD-3-Clause | [Project](https://github.com/eliben/pycparser) |
| mutagen | GPL-2.0-or-later | [Project](https://mutagen.readthedocs.io/) |
| PyCryptodome | Public Domain and BSD-2-Clause | [Project](https://www.pycryptodome.org/) |
| certifi | MPL-2.0 | [Project](https://github.com/certifi/python-certifi) |
| requests | Apache-2.0 | [Project](https://requests.readthedocs.io/) |
| charset-normalizer | MIT | [Project](https://charset-normalizer.readthedocs.io/) |
| idna | BSD-3-Clause | [Project](https://github.com/kjd/idna) |
| urllib3 | MIT | [Project](https://urllib3.readthedocs.io/) |
| SecretStorage | BSD-3-Clause | [Project](https://secretstorage.readthedocs.io/) |
| cryptography | Apache-2.0 | [Project](https://cryptography.io/) |
| Jeepney | MIT | [Project](https://jeepney.readthedocs.io/) |
| websockets | BSD-3-Clause | [Project](https://websockets.readthedocs.io/) |
| Meriyah | ISC | [Project](https://github.com/meriyah/meriyah) |
| Astring | MIT | [Project](https://github.com/davidbonnet/astring/) |

yt-dlp itself is Unlicense; its bundled executable includes separately licensed code, including GPL components. The source archive retains the full yt-dlp `AUTHORS` list and acknowledges its youtube-dl/youtube-dlc lineage. QuickJS credits Fabrice Bellard and Charlie Gordon under MIT; FFmpeg credits its developers under the terms of the supplied build. Consult the [main credits](../../CREDITS.md) and complete notices for each helper.
