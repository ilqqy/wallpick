"""The main picture of a Wallpaper Engine scene wallpaper.

A scene is packed in scene.pkg: a list of named entries followed by their
bytes. Pictures are .tex textures. A texture holds either an embedded image
file (JPEG, PNG, ...) or raw RGBA / DXT-compressed pixels, optionally LZ4
compressed. The layout follows RePKG (github.com/notscuffed/repkg), the
reference reader for these formats. Everything read here is untrusted, so
every size and offset is checked against the file before it is used.
"""

from io import BytesIO
import mmap
from pathlib import Path
import struct

from PIL import Image

try:
    import lz4.block
except ImportError:  # Only needed for compressed textures.
    lz4 = None


MAX_ENTRIES = 20_000
MAX_NAME = 255
MAX_IMAGES = 100
MAX_MIPMAPS = 32
MAX_MIPMAP_BYTES = 250_000_000
MAX_SIDE = 16384
# Texture formats (header) and FreeImage formats (embedded image files).
TEX_RGBA8888, TEX_DXT5, TEX_DXT3, TEX_DXT1 = 0, 4, 6, 7
PIXEL_FORMATS = {TEX_RGBA8888, TEX_DXT5, TEX_DXT3, TEX_DXT1}
FIF_UNKNOWN, FIF_MP4 = -1, 35
FLAG_GIF, FLAG_VIDEO = 4, 32
# Pillow's BCn decoder numbers: DXT1 = BC1, DXT3 = BC2, DXT5 = BC3.
BCN = {TEX_DXT1: 1, TEX_DXT3: 2, TEX_DXT5: 3}
# The background is a landscape picture; square atlases and masks are not.
MIN_RATIO = 1.2


class SceneError(Exception):
    """The scene has no usable picture or its files are malformed."""


class Reader:
    def __init__(self, data: bytes, offset: int = 0, end: int | None = None):
        self.data, self.pos = data, offset
        self.end = len(data) if end is None else end

    def take(self, count: int) -> bytes:
        if count < 0 or self.pos + count > self.end:
            raise SceneError("Truncated scene file")
        chunk = self.data[self.pos:self.pos + count]
        self.pos += count
        return chunk

    def i32(self) -> int:
        return struct.unpack("<i", self.take(4))[0]

    def cstring(self, limit: int = 32) -> str:
        """A NUL-terminated ASCII string, such as a magic value."""
        stop = self.data.find(b"\0", self.pos, min(self.end, self.pos + limit + 1))
        if stop < 0:
            raise SceneError("Malformed scene string")
        value = self.data[self.pos:stop].decode("ascii", "replace")
        self.pos = stop + 1
        return value


def pkg_entries(data: bytes) -> dict[str, tuple[int, int]]:
    """Entry name -> (start, end) byte range within the package."""
    reader = Reader(data)
    magic_length = reader.i32()
    if not 0 < magic_length <= 32 or not reader.take(magic_length).startswith(b"PKGV"):
        raise SceneError("Not a Wallpaper Engine scene package")
    count = reader.i32()
    if not 0 <= count <= MAX_ENTRIES:
        raise SceneError("Scene package lists too many files")
    raw = []
    for _ in range(count):
        length = reader.i32()
        if not 0 < length <= MAX_NAME:
            raise SceneError("Malformed scene package entry")
        name = reader.take(length).decode("utf-8", "replace")
        raw.append((name, reader.i32(), reader.i32()))
    base = reader.pos
    entries = {}
    for name, offset, length in raw:
        start = base + offset
        if offset < 0 or length < 0 or start + length > len(data):
            raise SceneError("Scene package entry lies outside the file")
        entries[name] = (start, start + length)
    return entries


def tex_header(reader: Reader) -> dict:
    if reader.cstring(16) != "TEXV0005" or reader.cstring(16) != "TEXI0001":
        raise SceneError("Unknown texture format")
    tex_format, flags, texture_width, texture_height, width, height, _ = struct.unpack("<7i", reader.take(28))
    return {"format": tex_format, "flags": flags, "texture": (texture_width, texture_height), "size": (width, height)}


def usable(header: dict) -> bool:
    width, height = header["size"]
    return (header["format"] in PIXEL_FORMATS and not header["flags"] & (FLAG_GIF | FLAG_VIDEO)
            and 0 < height and 0 < width <= MAX_SIDE and height <= MAX_SIDE and width >= height * MIN_RATIO)


def decode_tex(reader: Reader, header: dict) -> Image.Image:
    """The first (largest) mipmap of the first image, as a Pillow image."""
    magic = reader.cstring(16)
    if magic not in ("TEXB0001", "TEXB0002", "TEXB0003", "TEXB0004"):
        raise SceneError("Unknown texture container")
    version = int(magic[4:])
    if reader.i32() < 1:
        raise SceneError("Texture has no images")
    image_format = FIF_UNKNOWN
    if version >= 3:
        image_format = reader.i32()
    if version == 4:
        if reader.i32() == 1 and image_format == FIF_UNKNOWN:
            image_format = FIF_MP4
        # RePKG: only video textures use the version 4 mipmap layout.
        version = 4 if image_format == FIF_MP4 else 3
    if image_format == FIF_MP4:
        raise SceneError("Texture is a video")
    if not 0 < reader.i32() <= MAX_MIPMAPS:
        raise SceneError("Texture has no mipmaps")
    width, height = reader.i32(), reader.i32()
    compressed, expected = (reader.i32() == 1, reader.i32()) if version >= 2 else (False, 0)
    count = reader.i32()
    if not 0 < count <= MAX_MIPMAP_BYTES:
        raise SceneError("Texture data is too large")
    payload = reader.take(count)
    if compressed:
        if lz4 is None:
            raise SceneError("Compressed textures need the lz4 module")
        if not 0 < expected <= MAX_MIPMAP_BYTES:
            raise SceneError("Texture data is too large")
        try:
            payload = lz4.block.decompress(payload, uncompressed_size=expected)
        except (lz4.block.LZ4BlockError, ValueError) as error:
            raise SceneError("Texture data is corrupt") from error
    try:
        if image_format != FIF_UNKNOWN:
            # An image file stored as is; Pillow identifies it by its contents.
            image = Image.open(BytesIO(payload))
            image.load()
            return image
        if not (0 < width <= MAX_SIDE and 0 < height <= MAX_SIDE):
            raise SceneError("Texture has invalid dimensions")
        if header["format"] == TEX_RGBA8888:
            image = Image.frombytes("RGBA", (width, height), payload)
        else:
            image = Image.frombytes("RGBA", (width, height), payload, "bcn", BCN[header["format"]])
    except (OSError, ValueError, Image.DecompressionBombError) as error:
        raise SceneError("Texture could not be decoded") from error
    # Textures are padded to a power of two; the header gives the picture's size.
    crop = (min(width, header["size"][0]), min(height, header["size"][1]))
    return image.crop((0, 0, *crop)) if crop != (width, height) else image


def textures(folder: Path) -> list[tuple[bytes, int, int]]:
    """(data, start, end) of every .tex texture, packed or loose."""
    found = []
    package = folder / "scene.pkg"
    if package.is_file() and package.stat().st_size:
        # Mapped rather than read: packages run to hundreds of megabytes and
        # only the chosen texture is needed.
        with package.open("rb") as file:
            data = mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ)
        found += [(data, start, end) for name, (start, end) in pkg_entries(data).items()
                  if name.lower().endswith(".tex")]
    materials = folder / "materials"
    if not found and materials.is_dir():
        for path in sorted(materials.rglob("*.tex")):
            resolved = path.resolve()
            if resolved.is_file() and resolved.is_relative_to(folder.resolve()):
                data = resolved.read_bytes()
                found.append((data, 0, len(data)))
    return found


def main_picture(folder: Path) -> Image.Image:
    """The scene's largest landscape picture, which is its background."""
    candidates = []
    for data, start, end in textures(folder):
        reader = Reader(data, start, end)
        try:
            header = tex_header(reader)
        except SceneError:
            continue
        if usable(header):
            candidates.append((header["size"][0] * header["size"][1], header, reader))
    for _, header, reader in sorted(candidates, key=lambda candidate: candidate[0], reverse=True):
        try:
            return decode_tex(reader, header)
        except SceneError:
            continue
    raise SceneError("This scene has no full-size picture")
