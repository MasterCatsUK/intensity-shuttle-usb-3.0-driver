# Update the existing GitHub repository

Target: https://github.com/andrewvideo/intensity-shuttle-usb-3.0

## Repository contents

Upload or commit the contents of this source folder to the existing repository root, including hidden .gitignore/.gitattributes. README.md becomes the main GitHub README page automatically; docs/user-guide contains matching illustrated Markdown, HTML and PDF copies. Preserve licences and vendor sources. Do not upload the outer packaging folder as a nested repository.

The application code corresponds to 0.1.39. Documentation and the screenshot renderer have been refreshed for this upload. The existing 0.1.39 installer is byte-for-byte unchanged; its embedded Source.zip contains its original build-time documentation. Use the refreshed external source/guide assets for current reading.

## GitHub Release assets

Create a release tagged v0.1.39 after uploading the source. Attach the companion full installer, complete distribution ZIP, refreshed source ZIP and SHA256SUMS.txt from Release Assets. Use RELEASE-DESCRIPTION.md from the outer upload bundle as the release text. Binary packages/ZIPs are deliberately ignored by the repository .gitignore; put them in Releases instead of source commits.

The README links to the Releases page. Until assets are uploaded there, that link does not imply a downloadable installer is already published. Update the repository About description with ABOUT-TEXT.txt from the outer bundle; the current online description still names the earlier version.

Describe it as an experimental Apple-silicon development build. The unsigned installer/ad-hoc components, SIP-disabled runtime and unqualified fresh-machine installation must remain visible. The icon replacement was completed in 0.1.31; it does not provide signing/notarization qualification. Do not redistribute older0.1.30 artwork/packages.

Do not include Adobe SDK files, signing material, personal recordings or local diagnostics. Before a consumer release, follow the publisher checklist for Developer ID/notarization and qualification with SIP enabled. Nothing has been uploaded by this local preparation.
