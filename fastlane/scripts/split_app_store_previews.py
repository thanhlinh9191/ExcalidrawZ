#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print(
        "Missing dependency: Pillow. Install it with `python3 -m pip install Pillow`.",
        file=sys.stderr,
    )
    raise SystemExit(1)


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE_DIR = REPO_ROOT / "fastlane" / "previews" / "output"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "fastlane" / "screenshots"
DEFAULT_BASENAME = "AppStore_iPhone_Previews"
DEFAULT_SLICE_WIDTH = 1284
DEFAULT_GAP_WIDTH = 0
DEFAULT_LEGACY_LOCALE = "zh-Hans"
DEFAULT_OUTPUT_PREFIX = "iphone_6_7"


@dataclass(frozen=True)
class PreviewSource:
    locale: str
    path: Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Split localized App Store preview strips into fastlane screenshot "
            "locale folders."
        )
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=DEFAULT_SOURCE_DIR,
        help=f"Directory containing preview strips. Defaults to {DEFAULT_SOURCE_DIR.relative_to(REPO_ROOT)}.",
    )
    parser.add_argument(
        "--basename",
        default=DEFAULT_BASENAME,
        help=(
            "Preview strip basename. Localized files should be named "
            "<basename>.<locale>.png."
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"fastlane screenshot output directory. Defaults to {DEFAULT_OUTPUT_DIR.relative_to(REPO_ROOT)}.",
    )
    parser.add_argument(
        "--slice-width",
        type=int,
        default=DEFAULT_SLICE_WIDTH,
        help=f"Width of each App Store screenshot slice. Defaults to {DEFAULT_SLICE_WIDTH}.",
    )
    parser.add_argument(
        "--gap-width",
        type=int,
        default=DEFAULT_GAP_WIDTH,
        help=(
            "Optional horizontal gap between slices in the source strip. "
            "The gap is skipped and not exported. Defaults to 0."
        ),
    )
    parser.add_argument(
        "--slice-count",
        type=int,
        help=(
            "Optional number of full slices to export. Useful when a source strip "
            "contains unused trailing design area."
        ),
    )
    parser.add_argument(
        "--legacy-locale",
        default=DEFAULT_LEGACY_LOCALE,
        help=(
            "Locale to use for the legacy <basename>.png source. "
            f"Defaults to {DEFAULT_LEGACY_LOCALE}."
        ),
    )
    parser.add_argument(
        "--output-prefix",
        default=DEFAULT_OUTPUT_PREFIX,
        help=f"Output filename prefix. Defaults to {DEFAULT_OUTPUT_PREFIX}.",
    )
    parser.add_argument(
        "--locales",
        help="Optional comma-separated locale allow-list, such as en-US,zh-Hans.",
    )
    parser.add_argument(
        "--include-remainder",
        action="store_true",
        help="Also export the final slice when it is narrower than --slice-width.",
    )
    parser.add_argument(
        "--no-clean",
        action="store_true",
        help="Do not remove previously generated files with the same output prefix.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be written without creating files.",
    )
    return parser.parse_args()


def resolve_path(path: Path) -> Path:
    return path if path.is_absolute() else REPO_ROOT / path


def locale_filter(value: str | None) -> set[str] | None:
    if not value:
        return None
    return {item.strip() for item in value.split(",") if item.strip()}


def discover_sources(
    source_dir: Path,
    basename: str,
    legacy_locale: str,
    allowed_locales: set[str] | None,
) -> list[PreviewSource]:
    localized_pattern = re.compile(rf"^{re.escape(basename)}\.(?P<locale>.+)\.png$")
    sources_by_locale: dict[str, Path] = {}

    for path in sorted(source_dir.glob(f"{basename}.*.png")):
        match = localized_pattern.match(path.name)
        if not match:
            continue

        locale = match.group("locale")
        if allowed_locales is not None and locale not in allowed_locales:
            continue
        sources_by_locale[locale] = path

    legacy_path = source_dir / f"{basename}.png"
    if legacy_path.exists() and legacy_locale not in sources_by_locale:
        if allowed_locales is None or legacy_locale in allowed_locales:
            sources_by_locale[legacy_locale] = legacy_path

    return [
        PreviewSource(locale=locale, path=path)
        for locale, path in sorted(sources_by_locale.items())
    ]


def clean_generated_files(output_dir: Path, output_prefix: str, dry_run: bool) -> None:
    pattern = f"{output_prefix}_*.png"
    for path in sorted(output_dir.glob(pattern)):
        if dry_run:
            print(f"Would remove {path}")
        else:
            path.unlink()
            print(f"Removed {path}")


def split_source(
    source: PreviewSource,
    slice_width: int,
    gap_width: int,
    slice_count: int | None,
    output_dir: Path,
    output_prefix: str,
    include_remainder: bool,
    clean: bool,
    dry_run: bool,
) -> int:
    if slice_width <= 0:
        raise ValueError("--slice-width must be greater than 0.")
    if gap_width < 0:
        raise ValueError("--gap-width cannot be negative.")
    if slice_count is not None and slice_count <= 0:
        raise ValueError("--slice-count must be greater than 0.")

    with Image.open(source.path) as image:
        width, height = image.size
        stride = slice_width + gap_width
        available_slice_count = (width + gap_width) // stride
        full_slice_count = slice_count or available_slice_count
        if full_slice_count > available_slice_count:
            raise ValueError(
                f"{source.path} only contains {available_slice_count} full slice(s), "
                f"but --slice-count requested {full_slice_count}."
            )

        consumed_width = (
            full_slice_count * slice_width
            + max(0, full_slice_count - 1) * gap_width
        )
        remainder_width = max(0, width - consumed_width)

        if full_slice_count == 0:
            raise ValueError(
                f"{source.path} width {width}px is smaller than slice width {slice_width}px."
            )

        total_count = full_slice_count + (
            1 if include_remainder and remainder_width > 0 else 0
        )
        index_width = max(2, len(str(total_count)))
        locale_output_dir = output_dir / source.locale

        print(f"{source.locale}: {source.path} ({width}x{height})")
        if clean and locale_output_dir.exists():
            clean_generated_files(locale_output_dir, output_prefix, dry_run)

        if not dry_run:
            locale_output_dir.mkdir(parents=True, exist_ok=True)

        for index in range(full_slice_count):
            left = index * stride
            right = left + slice_width
            output_path = locale_output_dir / output_filename(
                index + 1,
                index_width,
                output_prefix,
            )
            if dry_run:
                print(f"Would write {output_path}")
            else:
                image.crop((left, 0, right, height)).save(output_path)
                print(f"Wrote {output_path}")

        if include_remainder and remainder_width > 0:
            output_path = locale_output_dir / output_filename(
                total_count,
                index_width,
                output_prefix,
            )
            left = full_slice_count * stride
            if dry_run:
                print(f"Would write {output_path}")
            else:
                image.crop((left, 0, width, height)).save(output_path)
                print(f"Wrote {output_path}")
        elif remainder_width > 0:
            if slice_count is not None:
                print(
                    f"Ignored trailing {remainder_width}px after "
                    f"{full_slice_count} requested slice(s) in {source.path}."
                )
            elif gap_width > 0 and remainder_width <= gap_width:
                print(f"Ignored trailing {remainder_width}px gap in {source.path}.")
            else:
                print(
                    f"Warning: ignored trailing {remainder_width}px in {source.path} "
                    f"({width}px does not match slice width {slice_width}px "
                    f"and gap width {gap_width}px).",
                    file=sys.stderr,
                )

        return total_count


def output_filename(index: int, index_width: int, output_prefix: str) -> str:
    return f"{output_prefix}_{index:0{index_width}d}.png"


def main() -> int:
    args = parse_args()
    source_dir = resolve_path(args.source_dir)
    output_dir = resolve_path(args.output_dir)
    allowed_locales = locale_filter(args.locales)

    if not source_dir.exists():
        print(f"Source directory does not exist: {source_dir}", file=sys.stderr)
        return 2

    sources = discover_sources(
        source_dir=source_dir,
        basename=args.basename,
        legacy_locale=args.legacy_locale,
        allowed_locales=allowed_locales,
    )

    if not sources:
        print(
            f"No preview strips found in {source_dir} for basename {args.basename}.",
            file=sys.stderr,
        )
        return 2

    exported = 0
    for source in sources:
        exported += split_source(
            source=source,
            slice_width=args.slice_width,
            gap_width=args.gap_width,
            slice_count=args.slice_count,
            output_dir=output_dir,
            output_prefix=args.output_prefix,
            include_remainder=args.include_remainder,
            clean=not args.no_clean,
            dry_run=args.dry_run,
        )

    action = "Would export" if args.dry_run else "Exported"
    print(f"{action} {exported} screenshot(s) for {len(sources)} locale(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
