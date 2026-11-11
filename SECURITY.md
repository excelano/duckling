# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately, using the **Report a vulnerability** button on the Security tab of this repository. If that button is not there, or you would rather not go through GitHub, email david.anderson@excelano.com instead. I aim to respond within seven days.

Please do not open public issues for security problems.

## Supported versions

The latest release receives security fixes. Older versions are not supported. A fix ships in a new release; update the way you installed.

## What Duckling can access

Duckling runs locally on your machine. It reads the files you queue, holds each in memory while it converts, and writes one output file per conversion where you chose, never over an existing file. Parsing is docling.rs's: Office and EPUB files are ZIP archives it reads member by member, PDFs are rendered in Rust and read by ONNX models, and nothing found inside a document is executed. It makes no network calls, has no auth layer, and can only read and write files your operating-system user already has access to.

## What Duckling stores

Duckling stores nothing outside the files you explicitly convert. There is no config directory, no telemetry, no analytics, and no remote logging.

## Third-party code in the package

The package carries ONNX Runtime (linked into the executable) and the Docling and PaddleOCR models. Each is pinned by version or by SHA-256 in the repository, and a fix in any of them reaches you through a new Duckling release.
