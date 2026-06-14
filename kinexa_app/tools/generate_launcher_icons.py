"""Gera PNGs do launcher a partir do logo transparente.

Ajuste SAFE para mudar o tamanho do logo na máscara do Android:
  0.62 = tamanho anterior
  0.50 = ~20% menor
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets" / "icons"
SRC_PNG = ROOT / "kinexa_logo_foreground_source.png"
SIZE = 1024
SAFE = 0.50  # safe zone do adaptive icon (66% máx. do canvas)


def main() -> None:
    src = Image.open(SRC_PNG).convert("RGBA")
    bbox = src.getbbox()
    if bbox is None:
        raise SystemExit(f"PNG sem conteúdo: {SRC_PNG}")

    logo = src.crop(bbox)
    target = int(SIZE * SAFE)
    scale = min(target / logo.width, target / logo.height)
    nw, nh = int(logo.width * scale), int(logo.height * scale)
    resized = logo.resize((nw, nh), Image.Resampling.LANCZOS)
    x = (SIZE - nw) // 2
    y = (SIZE - nh) // 2

    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fg.paste(resized, (x, y), resized)
    fg.save(ROOT / "kinexa_adaptive_foreground.png")

    launcher = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    launcher.paste(resized, (x, y), resized)
    launcher.save(ROOT / "kinexa_launcher.png")

    print(f"SAFE={SAFE} -> logo {nw}x{nh}px em canvas {SIZE}x{SIZE}")


if __name__ == "__main__":
    main()
