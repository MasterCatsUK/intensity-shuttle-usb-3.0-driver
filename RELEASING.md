# Preparing a GitHub release

This folder is ready to upload as a source repository. Version 0.1.31 replaces the older icon-pack artwork with an original SVHS cassette icon created from a text-only brief. No older artwork or Git history is included.

## Upload the source

1. Create an empty repository on github.com using your chosen name.
2. Upload this folder’s contents, including hidden .gitignore and .gitattributes files, or commit and push them with Git. Do not upload the parent outputs folder.
3. Keep LICENSE, COPYING, third-party notices, vendor sources and the user guide together with the code.
4. Set your own support/contact details in the repository. Review the publisher checklist before making release claims.

Adobe’s SDK is not included; developers obtain it separately. The README explains building. Generated packages and ZIPs are excluded from Git by .gitignore.

## Attach binaries as release assets

Create a GitHub Release for version 0.1.31 and attach the matching full installer, complete ZIP and SHA256SUMS.txt from the companion release folder. The complete ZIP contains the installer, source and illustrated guide. Do not attach older 0.1.30 packages or archives: those contain the previous restricted icon.

Describe this as an **experimental development build**, with its unsigned/ad-hoc signing and SIP-disabled runtime requirements clearly visible. Source publication is distinct from qualifying a normal consumer installer. The installer has not been signed or notarized with Developer ID. The icon update does not change that. Read docs/user-guide/Read Me.pdf before installation.

The 0.1.31 source builds and package checks were completed locally. The installed 0.1.30 features were tested on one Mac Studio; the 0.1.31 artwork/version update has not been installed or tested on a fresh Mac. Nothing has been published to GitHub by this preparation.

Do not include Adobe SDK downloads, private signing keys, personal recordings, local logs, or older artwork in repository history or release assets.
