# Submission notes

What a store submission needs from a person and no file supplies. The listing
text, and each store's notes for its reviewer, are `store-listing.toml`, and
what a release changed is `release-notes.toml`; the release apps push both. A
field edited here reaches nobody.

The message count in `microsoft-review-notes`'s second paragraph changes with
the binary: read it off the Windows App Certification Kit report before a
submission and update `store-listing.toml`.

## Capability justification

Partner Center asks once, when `runFullTrust` is first declared, and keeps the
answer against the product. 500 characters, newlines counted.

> Duckling is a full-trust Win32 desktop application packaged as MSIX. It
> needs this capability to run at all. It converts the files and folders a
> person chooses through Add, writing results to a folder they
> pick, entirely offline against bundled models. It makes no network
> connection, and uses no device.

## The answers a form asks

    Copyright and trademark   Excelano LLC
    Additional license terms  blank; the application is MIT and the
                              repository carries the license
    Short title               blank; the product name is already one word
    Privacy policy            https://excelano.com/legal/#duckling
    App Privacy (Apple)       Data Not Collected
    Price                     free

## Screenshots

Two frames on both stores, the Mac set repeating each in dark, taken by
`shots-winstore` and `shots-macstore` from the recipes in `windows/shots.ps1`
and `macos/shots.sh` over `demo/documents`, copied to a folder with a short
readable path because the path shows in the preview: a batch converting to
DocLang with a Word file's result selected, and a finished batch converting to
Markdown with `site-survey-report.pdf` previewed. The scanned PDF converted in
the queue is the offline-OCR claim photographed, so the Mac set is taken from
the arm64 bundle on an Apple silicon Mac, signed for development from the
commit being released; an `intel-mac` build fails every PDF row.
