# Publisher checklist — separate from the user guide

The local installer works on the tested setup, but that is not the same as a distribution-qualified consumer release.

1. Sign and notarize the installer, host, extensions and plug-ins using the appropriate Developer ID identities and entitlements. Apple explicitly says validation bypasses are for local development and should be reenabled before shipping system extensions: https://developer.apple.com/documentation/driverkit/debugging-and-testing-system-extensions
2. Qualify a fresh Apple-silicon Mac with SIP enabled, first-install approvals, capture, audio, both editors, removal and security restoration. The current first-time procedure was documented from the development setup, not qualified across new public machines.
3. Icon replacement completed in0.1.31: new text-generated SVHS project artwork. Confirm that future artwork contributions also have clear terms; do not reintroduce older icon-pack files.
4. Keep complete corresponding GPL/LGPL source, licence notices and exact build/version information available with binary distribution. Do not include Adobe's proprietary SDK headers in the public source archive.
5. Provide a support/contact route, known-issues list and checksums through a trusted distribution channel. Review screenshots/logs for private data. Do not claim endorsement by Apple, Adobe or Blackmagic Design.

The earlier source is already public. This0.1.39 update folder, installer assets and refreshed guide were prepared locally and have not been uploaded automatically.
