# Store listing text, German

The German half of `store-listing.md`, one file per language. The headings are
that file's headings and stay in English, because `fenster`'s parser reads both
files the same way; only what sits under them is German. Only the fields a store
shows a reader are here.

**Terminology is the application's own, out of `po/de.po`** — a listing that
calls a thing something the window does not teaches the customer a word the
product has no use for. Where the catalogue has a term, it wins.

**German runs longer than English.** Run `fenster/check-listing.ps1` on this file
after any edit to either language rather than trusting a translation to fit.
## Subtitle (Mac App Store, 30)

Dokumente zu DocLang, offline

## Promotional text (Mac App Store, 170)

Hinein: Word, PowerPoint, Excel, PDF und vierzig weitere Formate. Heraus: DocLang, Markdown, JSON, LaTeX, ODT oder DOCX — auf Ihrem Rechner, nichts wird gesendet.

## Short description (Microsoft Store, 500)

Duckling wandelt Dokumente in einfachen, strukturierten Text für Sprachmodelle und Suchindizes um: DocLang, Markdown, docling-JSON, LaTeX, ODT oder DOCX. Hinein: Word, PowerPoint, Excel, PDF, HTML, EPUB, OpenDocument, E-Mail und vierzig weitere Formate.

Gescannte Seiten lesen mitgelieferte OCR-Modelle: Duckling arbeitet offline, nichts verlässt Ihren Rechner. Der Download ist deshalb rund 600 MB groß.

Gelesen wird mit docling.rs, der Rust-Portierung von IBMs Docling.

## App features (Microsoft Store, up to 20 bullets of 200 characters)

    Liest Word, PowerPoint, Excel, PDF, HTML, EPUB, RTF, OpenDocument, Apple iWork, E-Mail, Visio und rund vierzig Formate insgesamt.
    Schreibt DocLang, Markdown, docling-JSON, ein DocLang-Archiv oder LaTeX. Oder ODT und DOCX, ein schlichtes Office-Dokument mit den Bildern in der Datei.
    Wandelt stapelweise um: Dateien oder einen ganzen Ordner hineinziehen, einmal wählen, Umwandeln drücken.
    Gescannte PDFs und Bilder lesen Modelle für Layout, Tabellenstruktur und OCR, die mit der Anwendung geliefert werden. Nach der Installation ist nichts nachzuladen.
    Ausgabe neben jede Datei oder in einen Ordner, und nie über eine vorhandene Datei.
    Eine Vorschau jedes Ergebnisses, mit Öffnen und Im Ordner zeigen.
    Arbeitet offline. Kein Konto, keine Telemetrie, nichts wird irgendwohin gesendet.
    Open Source, und quelloffen ist auch docling.rs, das die Dokumente liest.

## Description (both, written to 4,000)

Dokumente kommen als Word-Dateien, Foliensätze, Arbeitsmappen, PDFs und Scans. Was ein Sprachmodell, ein Suchindex oder ein versioniertes Repository will, ist einfacher, strukturierter Text. Duckling ist der Schritt dazwischen.

WAS HINEINGEHT

Word, PowerPoint und Excel, aktuelle wie alte. PDF, digital oder gescannt. HTML, EPUB, RTF, OpenDocument, Apple Pages, Numbers und Keynote, E-Mail, Visio, Markdown, CSV und rund vierzig Formate insgesamt, gelesen von docling.rs, der quelloffenen Rust-Portierung von IBMs Docling.

WAS HERAUSKOMMT

DocLang, die offene Dokumentauszeichnung für Sprachmodelle, fertig zum Öffnen in Segler, bloß oder als Archiv, das ein Seitenbild je Seite und jedes Bild mitführt. Markdown, mit Überschriften, Listen und Tabellen. Doclings JSON, das alles behält, was docling.rs gefunden hat. Oder LaTeX. Oder ein ODT- oder DOCX-Dokument, schlicht und gut gegliedert, mit den Bildern in der Datei; was dieses Format nicht halten kann, steht am Ergebnis, statt still wegzufallen.

WIE ES ARBEITET

Dateien oder Ordner auf das Fenster ziehen. Das Ausgabeformat wählen und ob die Ergebnisse neben jede Datei oder in einen Ordner gehen. Umwandeln drücken. Jede Zeile berichtet, während sie läuft, bei einem PDF Seite für Seite, und die Vorschau zeigt jedes Ergebnis mit einer Schaltfläche zum Öffnen oder zum Zeigen im Ordner. Eine vorhandene Datei wird nie überschrieben: aus einer zweiten report.md wird report (1).md.

Ein gescanntes PDF oder ein Bild lesen Modelle für Layout, Tabellenstruktur und OCR, die mit der Anwendung geliefert werden. Sie sind der größte Teil eines Downloads von rund 600 MB, und sie sind der Grund, warum danach nichts nachgeladen werden muss und die Anwendung ohne Netz arbeitet.

WAS ES NICHT TUT

Keinerlei Netzwerkverbindung. Kein Konto. Keine Telemetrie, keine Analyse, keine Absturzberichte. Nichts über Sie oder Ihre Dokumente wird irgendwohin gesendet, weil es nirgendwohin zu senden gibt.

Es bearbeitet nicht. Duckling wandelt um; zu berichtigen, was ein Modell falsch gelesen hat, ist Seglers Aufgabe, und die DocLang-Ausgabe ist, was die beiden verbindet.

OPEN SOURCE

Duckling ist Open Source unter der MIT-Lizenz, ebenso wie docling.rs, worauf es aufbaut: github.com/excelano/duckling.

## Release notes

*Neu in dieser Version*, aus `CHANGELOG.md`, neueste zuerst. 0.1.0 hat keine und
bekommt keine: als diese Fassung in den Store ging, hatte sie niemand von dort,
also war niemandem etwas zu sagen.

### 0.1.2

Duckling spricht Deutsch. Auf einem deutsch eingestellten Rechner erscheinen die Leiste, die Warteschlange, die Vorschau und jede Zeile der Statusleiste auf Deutsch, und es gibt nichts auszuwählen: Duckling übernimmt die Sprache, die der Rechner bereits eingestellt hat, und fällt für jede andere auf Englisch zurück.

Was eine Datei ist, bleibt, was die Datei sagt. Das Format, als das eine Zeile gelesen wurde, und die Endungen der Dateien, die docling.rs nicht liest, werden nicht übersetzt.

### 0.1.1

Duckling schreibt jetzt ODT und DOCX, neben DocLang, Markdown, docling-JSON und LaTeX: ein schlichtes, gut gegliedertes Office-Dokument aus dem, was gelesen wurde, mit den Bildern in der Datei. Was dieses Format nicht halten kann — eine Kopfzeile, eine Abbildung ohne eigenes Bild — steht am Ergebnis, statt still wegzufallen, und die Vorschau eines solchen Pakets zeigt das Dokument als Markdown.

Dokumente werden von docling.rs 1.37 gelesen.

## Keywords

**Mac App Store** (100 characters, comma-separated, no spaces after commas):

    Markdown,umwandeln,PDF,Word,DOCX,ODT,OCR,docling,DocLang,JSON,LaTeX,Dokument

**Microsoft Store** (seven terms):

    Markdown, umwandeln, PDF, Word, OCR, docling, DocLang
