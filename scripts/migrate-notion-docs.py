#!/usr/bin/env python3
"""
migrate-notion-docs.py — Notion export → loucedé local Documentation bundle.

Converts a Notion export (.zip containing Markdown & CSV) into a local
documentation structure embeddable in the loucedé macOS app bundle.

Usage:
    python3 migrate-notion-docs.py <export.zip> [--dry-run] [--output PATH]

Arguments:
    <export.zip>        Notion export zip (Markdown & CSV with subpages)
    --dry-run           Show what would be done without writing anything
    --output PATH       Destination folder (default:
                        ~/Developer/loucede/loucede/Resources/Documentation/)

What the script does:
    1. Decompresses the Notion export (handles nested Part-N.zip)
    2. Finds the complete CSV (with Catégorie + Emoji columns)
    3. Filters to État == 'Terminé', sorts by N° (float)
    4. For each tuto:
       - Matches the .md file via H1 ↔ CSV Titre
       - Strips Notion front-matter
       - Strips internal Notion links ([label](xxx.md) → label)
       - Converts <aside> callouts to > blockquotes (emoji-fusion rule)
       - Rewrites image paths to bundle://images/NN-slug-name.ext
       - Copies + renames images
    5. Writes manifest.json + tutos/*.md + images/*

Notion fields consumed (others ignored):
    Titre, Catégorie, N°, État, Emoji

Categories (canonical order):
    🚀 Démarrer / 🔧 Configurer loucedé / 💡 loucedé au quotidien
    💳 Compte et licence / 🛠️ Résolution de problèmes / 📚 Ressources

Author: Faab + Claude Code (2026-05-11)
"""

import argparse
import csv
import json
import re
import shutil
import sys
import tempfile
import unicodedata
import urllib.parse
import zipfile
from datetime import datetime, timezone
from pathlib import Path


# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------

# Canonical category order (cf. DocumentationView.categoryOrder in Swift app)
CATEGORIES_ORDER = [
    "🚀 Démarrer",
    "🔧 Configurer loucedé",
    "💡 loucedé au quotidien",
    "💳 Compte et licence",
    "🛠️ Résolution de problèmes",
    "📚 Ressources",
]

# Prefix for image paths in migrated .md files (consumed by Swift app)
IMAGE_BUNDLE_PREFIX = "bundle://images/"

# Filter column State
TARGET_STATUS = "Terminé"

# Default output dir
DEFAULT_OUTPUT = Path.home() / "Developer/loucede/loucede/Resources/Documentation"


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(
        description="Migrate Notion export to loucedé local docs bundle.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Example:\n  python3 migrate-notion-docs.py export.zip --dry-run",
    )
    parser.add_argument(
        "zip_path",
        type=Path,
        help="Path to the Notion export .zip",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without writing anything",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Destination folder (default: {DEFAULT_OUTPUT})",
    )
    return parser.parse_args()


# --------------------------------------------------------------------------
# Unzipping
# --------------------------------------------------------------------------

def unzip_export(zip_path: Path, tmp: Path) -> Path:
    """Decompress the Notion export (handles nested Part-N.zip).

    Returns the path of the folder containing both *.csv and *.md files
    (typically '<tmp>/Privé et partagé/Doc loucedé BDD').

    Raises FileNotFoundError if zip_path does not exist.
    Raises ValueError if no folder containing .csv + .md is found.
    """
    if not zip_path.exists():
        raise FileNotFoundError(f"Zip introuvable : {zip_path}")

    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(tmp)

    # Notion sometimes wraps the export in a nested zip (Part-1.zip)
    nested_zips = list(tmp.glob("*.zip"))
    if nested_zips:
        for nz in nested_zips:
            with zipfile.ZipFile(nz) as zf:
                zf.extractall(tmp)
            nz.unlink()

    # Walk to find the folder containing the .md tutos
    # (typically siblings: one .csv + many .md + optional subdirs with images)
    for csv_file in tmp.rglob("*.csv"):
        # Folder containing this CSV
        candidate = csv_file.parent
        md_files = list(candidate.glob("*.md"))
        if md_files:
            # CSV at root, .md at root → already correct
            return candidate
        # CSV sibling of a folder containing .md (Notion's nested layout)
        for sub in candidate.iterdir():
            if sub.is_dir() and list(sub.glob("*.md")):
                return sub

    raise ValueError("Aucun dossier contenant des .md trouvé dans le zip")


# --------------------------------------------------------------------------
# CSV parsing
# --------------------------------------------------------------------------

def find_csv(export_dir: Path) -> Path:
    """Find the complete CSV (header contains 'Catégorie' OR 'Emoji').

    Notion exports 2 CSVs:
        - filtered view (4 cols: Titre/État/N°/Emoji) — to ignore
        - complete view '_all.csv' (13 cols inc. Catégorie + Emoji) — to use

    Raises ValueError if no complete CSV is found.
    """
    # Search in export_dir parent too (CSV sometimes at sibling level)
    for search_root in [export_dir, export_dir.parent]:
        for csv_file in search_root.glob("*.csv"):
            with open(csv_file, encoding="utf-8-sig") as f:
                reader = csv.reader(f)
                header = next(reader, [])
            if "Catégorie" in header:
                return csv_file
    raise ValueError(
        "CSV complet (avec colonne Catégorie/Emoji) introuvable. "
        "Vérifier l'export Notion (vue complète, pas filtrée)."
    )


def parse_csv(csv_path: Path) -> list[dict]:
    """Parse the CSV using DictReader. utf-8-sig handles the BOM."""
    with open(csv_path, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def filter_and_sort(rows: list[dict]) -> list[dict]:
    """Filter to État == 'Terminé', sort by float(N°) ASC.

    Rows with unparseable N° are placed at the end (sorted alphabetically).
    """
    terminé = [r for r in rows if r.get("État", "").strip() == TARGET_STATUS]

    def sort_key(row):
        try:
            return (0, float(row.get("N°", "").strip()))
        except (ValueError, AttributeError):
            return (1, row.get("Titre", "").strip())

    return sorted(terminé, key=sort_key)


# --------------------------------------------------------------------------
# Slug + emoji utilities
# --------------------------------------------------------------------------

def normalize_slug(text: str) -> str:
    """NFD → strip diacritics → lowercase → [^a-z0-9]+ → '-' → strip.

    Examples:
        'Bienvenue dans loucedé' → 'bienvenue-dans-loucede'
        'Combien coûte loucedé ?' → 'combien-coute-loucede'
        '🚀 Démarrer' → 'demarrer' (after strip_emoji_prefix)
    """
    nfd = unicodedata.normalize("NFD", text)
    ascii_only = "".join(c for c in nfd if unicodedata.category(c) != "Mn")
    lower = ascii_only.lower()
    slug = re.sub(r"[^a-z0-9]+", "-", lower).strip("-")
    return slug


def strip_emoji_prefix(category: str) -> str:
    """Remove leading emoji + space from category name.

    Examples:
        '🚀 Démarrer' → 'Démarrer'
        '🛠️ Résolution de problèmes' → 'Résolution de problèmes'
    """
    return re.sub(r"^\S+\s+", "", category, count=1)


def is_emoji_only(text: str) -> bool:
    """Detect if text is essentially just emoji(s), no text content.

    Two heuristics combined:
    1. Short text (≤ 4 chars after strip) containing U+FE0F (Variation
       Selector-16) is an emoji. VS-16 is the official Unicode marker for
       'emoji presentation' on characters that have dual text/emoji forms
       (e.g., 'ℹ️' = U+2139 INFORMATION SOURCE + U+FE0F, where U+2139
       alone has Unicode category 'Ll' — Letter, lowercase — but is meant
       to render as an emoji here).
    2. Text composed only of symbol-category chars ('So', 'Sk', 'Sm') with
       no alphanumerics is an emoji (covers cases like '🤗', '✂️', '🇫🇷').

    Avoids false positives where '---' or '***' would be treated as
    emoji-isolated lines in <aside> callouts.
    """
    if not text:
        return False
    stripped = text.strip()
    if not stripped:
        return False
    # Heuristic 1: short text with VS-16 → emoji (covers 'ℹ️', '❤️', etc.)
    if len(stripped) <= 4 and "️" in stripped:
        return True
    # Heuristic 2: only 'So' (Symbol, Other) chars + no alphanumerics.
    # 'So' covers true emojis (🤗, ⬇️, ✂️, ✅...). We exclude 'Sm' (Symbol
    # Math: '=', '+', '<', '>') and 'Sk' (Symbol modifier) to avoid false
    # positives on '===', '+++', etc.
    has_alnum = any(c.isalnum() for c in stripped)
    has_symbol_other = any(
        unicodedata.category(c) == "So" for c in stripped
    )
    return not has_alnum and has_symbol_other


# --------------------------------------------------------------------------
# .md file matching
# --------------------------------------------------------------------------

def read_h1(md_path: Path) -> str:
    """Read the H1 (first line, '# Title') of a .md file."""
    with open(md_path, encoding="utf-8") as f:
        first_line = f.readline()
    return first_line.lstrip("# ").rstrip()


def find_md_file(md_dir: Path, csv_title: str) -> Path | None:
    """Find the .md file whose H1 matches csv_title.

    Returns the path, or None if no match (caller logs the error).
    """
    for md in md_dir.glob("*.md"):
        if read_h1(md) == csv_title:
            return md
    return None


# --------------------------------------------------------------------------
# Markdown transformations
# --------------------------------------------------------------------------

def strip_front_matter(content: str) -> str:
    """Remove Notion-style front-matter from a .md export.

    Notion exports structure (observed on the 6 V1 tutos):
        L01: # H1
        L02: (blank line)
        L03-L14: 'Clé: Valeur' front-matter (12-14 lines)
        L15: (blank line)
        L16+: real content

    The front-matter is NOT immediately after H1 — there's a blank line
    between them. So we can't naively cut at the first blank line.

    Algorithm:
        1. Keep H1.
        2. Skip blank line(s) after H1.
        3. If the next non-blank line looks like front-matter ('Clé: '
           pattern), skip all consecutive front-matter lines.
        4. Skip the blank line(s) after the front-matter.
        5. Keep the rest (real content).

    Defensive: if the lines after H1 don't look like front-matter
    (no 'Clé: ' pattern), nothing is stripped — only the empty line after
    H1 is preserved.
    """
    lines = content.splitlines()
    if not lines or not lines[0].startswith("#"):
        return content  # No H1, nothing to strip
    h1 = lines[0]

    # Front-matter line pattern: starts with word/accented chars (including '°'
    # for 'N°'), may contain spaces and slashes, then ': ' separator
    fm_pattern = re.compile(r"^[\w\sÀ-ÿ°/]+:\s")

    i = 1
    # Skip blank lines after H1
    while i < len(lines) and lines[i].strip() == "":
        i += 1
    # Defensive: only strip if the next block looks like front-matter
    if i < len(lines) and fm_pattern.match(lines[i]):
        # Skip consecutive front-matter lines (non-blank + matching pattern)
        while i < len(lines) and lines[i].strip() != "" and fm_pattern.match(lines[i]):
            i += 1
        # Skip the blank line(s) after the front-matter
        while i < len(lines) and lines[i].strip() == "":
            i += 1

    # Reconstruct: H1 + blank line + remaining content
    return "\n".join([h1, ""] + lines[i:])


def strip_internal_links(content: str) -> tuple[str, int]:
    """Convert [label](xxx.md) → label (text only, no link).

    Does NOT touch http(s):// links even if they end in .md (negative
    look-ahead). Returns (transformed_content, count_removed).

    Example:
        '[GitHub Releases](Installer.md)' → 'GitHub Releases'
        '[GitHub page](https://github.com/x/README.md)' → unchanged
    """
    pattern = re.compile(r"\[([^\]]+)\]\((?!https?://)([^)]+\.md)\)")
    matches = pattern.findall(content)
    transformed = pattern.sub(r"\1", content)
    return transformed, len(matches)


def transform_aside(content: str) -> str:
    """Convert <aside>...</aside> blocks to > blockquote Markdown.

    Rules (decision F2 from spec):
    - If the <aside> opens with an isolated emoji on its own line followed
      by a blank line, fuse the emoji with the first non-blank content line.
    - Otherwise (no emoji-isolated line), prefix each line with '> '
      verbatim.
    - Blank lines inside the block become '>' (empty blockquote line).

    The regex is non-greedy (.*?) so consecutive <aside> blocks don't merge.
    """
    pattern = re.compile(r"<aside>(.*?)</aside>", re.DOTALL)

    def convert_one(match: re.Match) -> str:
        inner = match.group(1).strip("\n")
        lines = inner.split("\n")

        # Detect: emoji-only first line + blank second line
        emoji_fusion = (
            len(lines) >= 2
            and is_emoji_only(lines[0].strip())
            and lines[1].strip() == ""
        )

        if emoji_fusion:
            emoji = lines[0].strip()
            # Find first non-blank content line after the blank separator
            for i in range(2, len(lines)):
                if lines[i].strip() != "":
                    lines[i] = f"{emoji} {lines[i]}"
                    content_lines = lines[i:]
                    break
            else:
                content_lines = lines[2:]  # All blank, fallback
        else:
            content_lines = lines

        # Strip trailing empty lines
        while content_lines and content_lines[-1].strip() == "":
            content_lines.pop()

        # Prefix with '> ' (or just '>' for blank lines)
        return "\n".join(
            f"> {line}" if line.strip() else ">"
            for line in content_lines
        )

    return pattern.sub(convert_one, content)


def rewrite_image_paths(
    content: str, seq: int, slug: str
) -> tuple[str, list[tuple[str, str]]]:
    """Rewrite ![alt](encoded/path/image.ext) → bundle://images/NN-slug-name.ext.

    Returns:
        (transformed_content, list of (source_rel_path_decoded, dest_name))
    """
    pattern = re.compile(r"!\[([^\]]*)\]\(([^)]+)\)")
    images_to_copy: list[tuple[str, str]] = []

    def rewrite_one(match: re.Match) -> str:
        alt = match.group(1)
        raw_path = match.group(2)
        # Don't rewrite external URLs
        if raw_path.startswith(("http://", "https://")):
            return match.group(0)
        # URL-decode (Notion encodes spaces as %20, accents as %XX)
        decoded = urllib.parse.unquote(raw_path)
        basename = Path(decoded).name
        name_part = Path(basename).stem
        ext = Path(basename).suffix
        # Normalize the image name (slug-style)
        normalized_name = normalize_slug(name_part)
        dest_name = f"{seq:02d}-{slug}-{normalized_name}{ext}"
        new_url = f"{IMAGE_BUNDLE_PREFIX}{dest_name}"
        images_to_copy.append((decoded, dest_name))
        return f"![{alt}]({new_url})"

    transformed = pattern.sub(rewrite_one, content)
    return transformed, images_to_copy


# --------------------------------------------------------------------------
# Per-tuto processing
# --------------------------------------------------------------------------

def process_tuto(
    row: dict,
    seq: int,
    export_dir: Path,
    warnings: list[str],
) -> dict | None:
    """Process one tuto: find .md, apply transformations, build manifest entry.

    Returns dict for manifest (with internal _transformed_content +
    _images_to_copy keys for later writing), or None if skipped (error).
    Appends to warnings list for non-fatal issues.
    """
    title = row.get("Titre", "").strip()
    emoji = (row.get("Emoji", "") or "").strip() or None
    category = (row.get("Catégorie", "") or "").strip()
    notion_number = (row.get("N°", "") or "").strip()

    # Validations
    if not title:
        msg = f"  ❌ Tuto sans titre (N°={notion_number}) — IGNORÉ"
        print(msg)
        warnings.append(msg)
        return None

    if emoji is None:
        msg = f"  ⚠️  '{title}' : pas d'emoji dans CSV (migré avec emoji=null)"
        print(msg)
        warnings.append(msg)

    if category not in CATEGORIES_ORDER:
        msg = f"  ❌ '{title}' : catégorie inconnue '{category}' — IGNORÉ"
        print(msg)
        warnings.append(msg)
        return None

    md_file = find_md_file(export_dir, title)
    if md_file is None:
        msg = f"  ❌ '{title}' : .md introuvable (H1 ne matche pas) — IGNORÉ"
        print(msg)
        warnings.append(msg)
        return None

    slug = normalize_slug(title)
    dest_md_name = f"{seq:02d}-{slug}.md"

    # Read + transform pipeline
    try:
        raw_content = md_file.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        msg = f"  ❌ '{title}' : lecture .md échouée ({e}) — IGNORÉ"
        print(msg)
        warnings.append(msg)
        return None

    content = strip_front_matter(raw_content)
    content, removed_links = strip_internal_links(content)
    content = transform_aside(content)
    content, images_referenced = rewrite_image_paths(content, seq, slug)

    # Validate images exist on disk
    valid_images: list[tuple[Path, str]] = []
    for src_rel, dest_name in images_referenced:
        src_abs = export_dir / src_rel
        if not src_abs.exists():
            msg = f"  ⚠️  '{title}' : image manquante '{src_rel}' — lien laissé dans le .md mais NON listée dans manifest"
            print(msg)
            warnings.append(msg)
            continue
        valid_images.append((src_abs, dest_name))

    print(
        f"  ✅ '{title}' → {dest_md_name} "
        f"({len(valid_images)} images, {removed_links} liens internes nettoyés)"
    )

    return {
        "id": f"{seq:02d}-{slug}",
        "sequence": seq,
        "notion_number": notion_number,
        "title": title,
        "emoji": emoji,
        "category_id": normalize_slug(strip_emoji_prefix(category)),
        "file": f"tutos/{dest_md_name}",
        "images": [f"images/{name}" for _, name in valid_images],
        # Internal-use only (stripped before writing manifest.json):
        "_transformed_content": content,
        "_images_to_copy": valid_images,
    }


# --------------------------------------------------------------------------
# Manifest building + output writing
# --------------------------------------------------------------------------

def build_manifest(tutos: list[dict], source_zip_name: str) -> dict:
    """Build the final manifest.json structure.

    All 6 canonical categories are declared (even empty ones for V1) —
    the Swift app filters empty categories at display time.
    """
    return {
        "version": "1.0",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source_zip": source_zip_name,
        "categories": [
            {
                "id": normalize_slug(strip_emoji_prefix(cat)),
                "title": cat,
                "order": i + 1,
            }
            for i, cat in enumerate(CATEGORIES_ORDER)
        ],
        "tutos": [
            {k: v for k, v in t.items() if not k.startswith("_")}
            for t in tutos
        ],
    }


def write_outputs(manifest: dict, tutos: list[dict], output_dir: Path) -> None:
    """Write manifest.json + tutos/*.md + images/* to output_dir.

    Wipes existing Documentation/ first for idempotency. Subsequent runs
    fully replace the previous export.
    """
    if output_dir.exists():
        shutil.rmtree(output_dir)
    (output_dir / "tutos").mkdir(parents=True)
    (output_dir / "images").mkdir(parents=True)

    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    for tuto in tutos:
        md_dest = output_dir / tuto["file"]
        md_dest.write_text(tuto["_transformed_content"], encoding="utf-8")
        for src_abs, dest_name in tuto["_images_to_copy"]:
            shutil.copy2(src_abs, output_dir / "images" / dest_name)


# --------------------------------------------------------------------------
# Dry-run preview
# --------------------------------------------------------------------------

def print_dry_run_preview(manifest: dict, tutos: list[dict]) -> None:
    """Print manifest + sample transformed file for dry-run inspection."""
    print()
    print("=== Mode dry-run : aucun fichier écrit ===")
    print()
    print("Preview manifest.json :")
    print(json.dumps(manifest, indent=2, ensure_ascii=False))
    print()
    if tutos:
        sample = tutos[0]
        print(f"Preview du 1er tuto transformé ({sample['file']}) :")
        print("─" * 60)
        print(sample["_transformed_content"])
        print("─" * 60)
        all_images = [
            (str(src), dest)
            for t in tutos
            for src, dest in t["_images_to_copy"]
        ]
        if all_images:
            print()
            print(f"Images qui seraient copiées ({len(all_images)}) :")
            for src, dest in all_images:
                print(f"  {Path(src).name} → images/{dest}")


# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------

def print_summary(
    tutos: list[dict],
    rows_total: int,
    rows_terminé: int,
    warnings: list[str],
) -> None:
    """Print the final migration summary."""
    image_count = sum(len(t["_images_to_copy"]) for t in tutos)
    skipped = rows_terminé - len(tutos)
    print()
    print("=== Récap ===")
    print(f"Tutos en État='Terminé' (CSV)   : {rows_terminé}/{rows_total}")
    print(f"Tutos exportés                  : {len(tutos)}")
    print(f"Tutos ignorés                   : {skipped}")
    print(f"Images copiées                  : {image_count}")
    print(f"Warnings                        : {len(warnings)}")


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main() -> int:
    """Orchestrate the migration end-to-end."""
    args = parse_args()
    warnings: list[str] = []

    print("=== Migration Notion → loucedé Documentation ===")
    print(f"Source       : {args.zip_path.name}")
    print(f"Destination  : {args.output}")
    if args.dry_run:
        print("Mode         : DRY RUN (aucune écriture)")
    print()

    with tempfile.TemporaryDirectory(prefix="notion-migrate-") as tmp_str:
        tmp = Path(tmp_str)
        try:
            export_dir = unzip_export(args.zip_path, tmp)
        except (FileNotFoundError, zipfile.BadZipFile, ValueError) as e:
            print(f"❌ Échec de la décompression : {e}", file=sys.stderr)
            return 1

        md_count = len(list(export_dir.glob("*.md")))
        img_count = sum(
            1
            for sub in export_dir.iterdir()
            if sub.is_dir()
            for _ in sub.iterdir()
        )
        print(f"Décompression OK ({md_count} .md, {img_count} images)")

        try:
            csv_path = find_csv(export_dir)
        except ValueError as e:
            print(f"❌ {e}", file=sys.stderr)
            return 1

        print(f"CSV détecté : {csv_path.name}")
        rows = parse_csv(csv_path)
        terminé_rows = filter_and_sort(rows)
        print(f"Tutos en État='Terminé' : {len(terminé_rows)}/{len(rows)}")
        print()

        tutos: list[dict] = []
        for seq, row in enumerate(terminé_rows, start=1):
            print(f"[{seq}/{len(terminé_rows)}]", end=" ")
            tuto = process_tuto(row, seq, export_dir, warnings)
            if tuto is not None:
                tutos.append(tuto)

        manifest = build_manifest(tutos, args.zip_path.name)

        if args.dry_run:
            print_dry_run_preview(manifest, tutos)
        else:
            try:
                write_outputs(manifest, tutos, args.output)
                print()
                print(f"Output écrit dans : {args.output}")
            except OSError as e:
                print(f"❌ Échec de l'écriture : {e}", file=sys.stderr)
                return 1

        print_summary(tutos, len(rows), len(terminé_rows), warnings)
        print()
        print("✅ Migration terminée." if not args.dry_run else "✅ Dry-run terminé.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
