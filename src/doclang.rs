//! What docling.rs leaves to the caller when the output is DocLang: the page
//! breaks a PDF's markup needs, the picture assets the markup names, and the
//! archive that carries both with the page images.
//!
//! The DocLang specification's archive is `document.xml` plus optional
//! `pages/N.png` and `assets/`. docling.rs's own archive writer emits the
//! markup alone, and its markup for a PDF carries no `<page_break/>` where
//! the reference Python export carries one per page boundary (measured
//! 2026-09-05 on `normal_4pages.pdf`: four `PageInfo` nodes, no breaks,
//! against three breaks in the reference archive). DESIGN.md §4.
//!
//! Author: David M. Anderson
//! Built with AI assistance (Claude, Anthropic)

use std::collections::HashMap;

use docling::{DoclingDocument, Node};
use sha2::{Digest, Sha256};

/// Put a `<page_break/>` before every page after the first, when the
/// converter has marked the pages and written no breaks. A PDF or image
/// conversion marks each page with a `PageInfo` node; the spreadsheet, slide
/// and RTF backends write breaks themselves and are left alone. Without
/// this, a review tool splitting on breaks sees one page, and an archive
/// may carry one page image.
pub fn insert_page_breaks(document: &mut DoclingDocument) {
    if document.nodes.iter().any(|n| matches!(n, Node::PageBreak)) {
        return;
    }
    let mut seen_page = false;
    let mut nodes = Vec::with_capacity(document.nodes.len() + 8);
    for node in document.nodes.drain(..) {
        if matches!(node, Node::PageInfo { .. }) {
            if seen_page {
                nodes.push(Node::PageBreak);
            }
            seen_page = true;
        }
        nodes.push(node);
    }
    document.nodes = nodes;
}

/// How many pages the markup declares: the breaks plus one. The archive may
/// carry no page image beyond this count.
pub fn page_count(xml: &str) -> usize {
    xml.matches("<page_break/>").count() + 1
}

/// The `assets/…png` files the markup refers to, with their bytes. The
/// exporter names each image-bearing picture `assets/image_NNNNNN_<sha256>.png`
/// with the hash over the picture's source bytes, in document order, and
/// writes nothing. This finds every picture with an image anywhere in the
/// tree, hashes it the same way, and pairs each name in the markup with the
/// bytes whose hash it carries; a name whose hash matches nothing is left
/// out rather than guessed at. Sources that are not PNG are re-encoded,
/// because the name says `.png` and a reader is entitled to believe it.
pub fn assets(document: &DoclingDocument, xml: &str) -> Vec<(String, Vec<u8>)> {
    let mut by_hash: HashMap<String, &[u8]> = HashMap::new();
    for node in &document.nodes {
        collect_images(node, &mut by_hash);
    }
    let mut out = Vec::new();
    let mut rest = xml;
    while let Some(start) = rest.find("<src uri=\"assets/") {
        rest = &rest[start + "<src uri=\"".len()..];
        let Some(end) = rest.find('"') else { break };
        let name = &rest[..end];
        rest = &rest[end..];
        let hash = name
            .strip_suffix(".png")
            .and_then(|n| n.rsplit('_').next())
            .unwrap_or_default();
        if let Some(bytes) = by_hash.get(hash) {
            if let Some(png) = as_png(bytes) {
                out.push((name.to_owned(), png));
            }
        }
    }
    out
}

fn collect_images<'a>(node: &'a Node, by_hash: &mut HashMap<String, &'a [u8]>) {
    match node {
        Node::Picture {
            image: Some(img), ..
        } => {
            by_hash.insert(sha256_hex(&img.data), &img.data);
        }
        Node::Group { children, .. } => children.iter().for_each(|c| collect_images(c, by_hash)),
        Node::Furniture { inner, .. }
        | Node::Commented { inner, .. }
        | Node::Located { inner, .. }
        | Node::DoclangOnly(inner) => collect_images(inner, by_hash),
        _ => {}
    }
}

fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

/// The bytes as PNG: unchanged when they already are, re-encoded when they
/// decode as something else, and `None` when they decode as nothing.
pub fn as_png(bytes: &[u8]) -> Option<Vec<u8>> {
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Some(bytes.to_vec());
    }
    let decoded = image::load_from_memory(bytes).ok()?;
    let mut out = std::io::Cursor::new(Vec::new());
    decoded.write_to(&mut out, image::ImageFormat::Png).ok()?;
    Some(out.into_inner())
}

/// One page image per entry, numbered from 1, as PNG.
pub type Pages = Vec<Vec<u8>>;

/// The archive: the two OPC parts docling.rs's writer emits, byte for byte
/// the reference package's, then `document.xml`, then the pages and assets.
/// Pages beyond what the markup declares are dropped, since the
/// specification says a page file past the last segment is out of bounds.
pub fn archive(xml: &str, pages: &Pages, assets: &[(String, Vec<u8>)]) -> Vec<u8> {
    let document = format!("{xml}\n");
    let allowed = page_count(xml);
    let mut entries: Vec<(String, &[u8])> = vec![
        ("[Content_Types].xml".to_owned(), CONTENT_TYPES.as_bytes()),
        ("_rels/.rels".to_owned(), RELS.as_bytes()),
        ("document.xml".to_owned(), document.as_bytes()),
    ];
    for (i, png) in pages.iter().take(allowed).enumerate() {
        entries.push((format!("pages/{}.png", i + 1), png.as_slice()));
    }
    for (name, bytes) in assets {
        entries.push((name.clone(), bytes.as_slice()));
    }
    docling::dclx::zip_bytes(entries.iter().map(|(n, b)| (n.as_str(), *b)))
}

const CONTENT_TYPES: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Default Extension="jpg" ContentType="image/jpeg"/>
  <Default Extension="jpeg" ContentType="image/jpeg"/>
  <Default Extension="webp" ContentType="image/webp"/>
  <Override PartName="/document.xml" ContentType="application/vnd.doclang.document+xml"/>
</Types>
"#;

const RELS: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://doclang.ai/ns/package/2026/relationships/document"
    Target="document.xml"/>
</Relationships>
"#;

#[cfg(test)]
mod tests {
    use super::*;

    fn page(n: usize) -> Node {
        Node::PageInfo {
            page_no: n,
            width: 612.0,
            height: 792.0,
        }
    }

    #[test]
    fn breaks_go_between_pages_and_only_when_absent() {
        let mut doc = DoclingDocument::new("t");
        doc.nodes = vec![
            page(1),
            Node::Paragraph { text: "a".into() },
            page(2),
            Node::Paragraph { text: "b".into() },
            page(3),
        ];
        insert_page_breaks(&mut doc);
        let breaks = doc
            .nodes
            .iter()
            .filter(|n| matches!(n, Node::PageBreak))
            .count();
        assert_eq!(breaks, 2);
        assert!(matches!(doc.nodes[2], Node::PageBreak));
        insert_page_breaks(&mut doc);
        assert_eq!(
            doc.nodes
                .iter()
                .filter(|n| matches!(n, Node::PageBreak))
                .count(),
            2
        );
        assert_eq!(page_count(&doc.export_to_doclang()), 3);
    }

    #[test]
    fn a_document_without_pages_gets_no_breaks() {
        let mut doc = DoclingDocument::new("t");
        doc.nodes = vec![Node::Paragraph { text: "a".into() }];
        insert_page_breaks(&mut doc);
        assert_eq!(doc.nodes.len(), 1);
        assert_eq!(page_count(&doc.export_to_doclang()), 1);
    }

    #[test]
    fn assets_pair_the_markup_names_with_the_bytes() {
        let png = as_png(&tiny_bmp()).unwrap();
        let mut doc = DoclingDocument::new("t");
        doc.nodes = vec![Node::Picture {
            caption: Some("A".into()),
            caption_href: None,
            image: Some(docling::PictureImage {
                mimetype: "image/bmp".into(),
                width: 1,
                height: 1,
                data: tiny_bmp(),
            }),
            classification: None,
        }];
        let xml = doc.export_to_doclang();
        let found = assets(&doc, &xml);
        assert_eq!(found.len(), 1, "{xml}");
        assert!(found[0].0.starts_with("assets/image_000000_"));
        assert!(found[0].0.ends_with(".png"));
        assert_eq!(found[0].1, png, "re-encoded to PNG");
        assert!(xml.contains(&found[0].0));
    }

    #[test]
    fn archive_drops_pages_past_the_last_segment() {
        let xml = "<doclang version=\"0.7\">\n  <text>a</text>\n  <page_break/>\n  <text>b</text>\n</doclang>";
        let pages: Pages = vec![vec![1], vec![2], vec![3]];
        let bytes = archive(xml, &pages, &[("assets/x.png".into(), vec![9])]);
        let names: Vec<String> = {
            let mut zip = zip_names(&bytes);
            zip.sort();
            zip
        };
        assert_eq!(
            names,
            [
                "[Content_Types].xml",
                "_rels/.rels",
                "assets/x.png",
                "document.xml",
                "pages/1.png",
                "pages/2.png"
            ]
        );
    }

    fn zip_names(bytes: &[u8]) -> Vec<String> {
        // The central directory's file names, read the plain way: each
        // header is signature, 42 bytes of fields, then the name.
        let mut names = Vec::new();
        let mut i = 0;
        while i + 46 <= bytes.len() {
            if bytes[i..i + 4] == [0x50, 0x4b, 0x01, 0x02] {
                let n = u16::from_le_bytes([bytes[i + 28], bytes[i + 29]]) as usize;
                names.push(String::from_utf8_lossy(&bytes[i + 46..i + 46 + n]).into_owned());
                i += 46 + n;
            } else {
                i += 1;
            }
        }
        names
    }

    /// A one-pixel 24-bit BMP, the smallest image the decoder set reads.
    fn tiny_bmp() -> Vec<u8> {
        let mut b = Vec::new();
        b.extend_from_slice(b"BM");
        b.extend_from_slice(&58u32.to_le_bytes());
        b.extend_from_slice(&0u32.to_le_bytes());
        b.extend_from_slice(&54u32.to_le_bytes());
        b.extend_from_slice(&40u32.to_le_bytes());
        b.extend_from_slice(&1i32.to_le_bytes());
        b.extend_from_slice(&1i32.to_le_bytes());
        b.extend_from_slice(&1u16.to_le_bytes());
        b.extend_from_slice(&24u16.to_le_bytes());
        b.extend_from_slice(&0u32.to_le_bytes());
        b.extend_from_slice(&4u32.to_le_bytes());
        b.extend_from_slice(&[0u8; 16]);
        b.extend_from_slice(&[0x40, 0x80, 0xc0, 0]);
        b
    }
}
