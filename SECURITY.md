# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately through GitHub Security Advisories at https://github.com/excelano/duckling/security/advisories/new. If you would rather not use GitHub, email david.anderson@excelano.com instead. I aim to respond within seven days.

Please do not open public issues for security problems.

## Supported versions

The latest 0.x release receives security fixes. Older versions are not supported.

## What Duckling can access

Duckling runs locally on your machine. It reads the files you queue, holds each in memory while it converts, and writes one output file per conversion where you chose, never over an existing file. Parsing is docling.rs's: Office and EPUB files are ZIP archives it reads member by member, PDFs are rendered by pdfium and read by ONNX models, and nothing found inside a document is executed. It makes no network calls, has no auth layer, and can only read and write files your operating-system user already has access to.

## What Duckling stores

Duckling stores nothing outside the files you explicitly convert. There is no config directory, no telemetry, no analytics, and no remote logging.

## Third-party code in the package

The package carries ONNX Runtime (linked into the executable), pdfium (a shared library beside it), and the Docling and PaddleOCR models. Each is pinned by version or by SHA-256 in the repository, and a fix in any of them reaches you through a new Duckling release.

## Verifying releases

Every GitHub release includes a `.sha256` file next to each archive listing its SHA-256 hash. Verify any download before running it. Release artifacts are built by GitHub Actions from a tagged commit; the workflows in this repository are public and auditable.
