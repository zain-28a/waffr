from pathlib import Path

UPLOAD_DIR = Path(__file__).resolve().parent / "uploads" / "avatars"
MAX_BYTES = 2 * 1024 * 1024

_JPEG = (b"\xff\xd8\xff", ".jpg", "image/jpeg")
_PNG = (b"\x89PNG\r\n\x1a\n", ".png", "image/png")


def _detect(data: bytes) -> tuple[str, str] | None:
    if data.startswith(_JPEG[0]):
        return _JPEG[1], _JPEG[2]
    if data.startswith(_PNG[0]):
        return _PNG[1], _PNG[2]
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ".webp", "image/webp"
    return None


def _paths_for(user_id: int) -> list[Path]:
    if not UPLOAD_DIR.exists():
        return []
    return sorted(UPLOAD_DIR.glob(f"{user_id}.*"))


def media_type_for(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".png":
        return "image/png"
    if suffix == ".webp":
        return "image/webp"
    return "image/jpeg"


def has_photo(user_id: int) -> bool:
    return photo_path(user_id) is not None


def photo_path(user_id: int) -> Path | None:
    for path in _paths_for(user_id):
        if path.is_file():
            return path
    return None


def delete_photo(user_id: int) -> bool:
    removed = False
    for path in _paths_for(user_id):
        path.unlink(missing_ok=True)
        removed = True
    return removed


def save_photo(user_id: int, data: bytes) -> str:
    detected = _detect(data)
    if detected is None:
        raise ValueError("unsupported image")
    if len(data) > MAX_BYTES:
        raise ValueError("image too large")

    ext, media_type = detected
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    delete_photo(user_id)
    dest = UPLOAD_DIR / f"{user_id}{ext}"
    dest.write_bytes(data)
    return media_type
