"""
Convert all Play Store SVGs to JPG format.
Uses cairosvg for SVG rasterization + Pillow for JPG output.
"""

import os
import sys
from pathlib import Path

# Add the cairosvg script directory to PATH if needed
try:
    from cairosvg import svg2png
except ImportError:
    print("cairosvg not found, attempting to use direct path...")
    sys.path.insert(0, os.path.expanduser(r"~\AppData\Roaming\Python\Python314\Scripts"))
    from cairosvg import svg2png

from PIL import Image
import io
import glob

def convert_svg_to_jpg(svg_path, jpg_path, width=1080, height=1920, quality=92):
    """Convert SVG file to JPG using cairosvg + Pillow."""
    print(f"  Converting: {svg_path.name} -> {jpg_path.name}")
    
    # Read SVG content
    with open(svg_path, "rb") as f:
        svg_data = f.read()
    
    # Convert SVG to PNG bytes at the specified resolution
    png_data = svg2png(bytestring=svg_data, output_width=width, output_height=height)
    
    # Open PNG data with Pillow
    img = Image.open(io.BytesIO(png_data))
    
    # Convert RGBA to RGB (JPG doesn't support alpha)
    if img.mode == "RGBA":
        # Create white background
        background = Image.new("RGB", img.size, (10, 10, 26))
        background.paste(img, mask=img.split()[3])  # Use alpha channel as mask
        img = background
    elif img.mode != "RGB":
        img = img.convert("RGB")
    
    # Save as JPG
    img.save(jpg_path, "JPEG", quality=quality, optimize=True)
    print(f"    -> Saved: {jpg_path} ({img.size[0]}x{img.size[1]}px)")
    return True

def main():
    # Base directory: project root (parent of scripts/)
    script_dir = Path(__file__).parent
    project_dir = script_dir.parent
    svg_dir = project_dir / "assets" / "playstore_graphics"
    output_dir = project_dir / "assets" / "playstore_graphics"
    
    # Find all SVG files
    svg_files = sorted(svg_dir.glob("*.svg"))
    
    if not svg_files:
        print(f"No SVG files found in {svg_dir}")
        return
    
    print(f"Found {len(svg_files)} SVG files to convert\n")
    
    success_count = 0
    for svg_path in svg_files:
        # Generate JPG filename: same name but .jpg extension
        jpg_path = output_dir / f"{svg_path.stem}.jpg"
        
        # Skip if JPG already exists and is newer than SVG
        if jpg_path.exists() and jpg_path.stat().st_mtime > svg_path.stat().st_mtime:
            print(f"  Skipping (up to date): {jpg_path.name}")
            continue
        
        try:
            convert_svg_to_jpg(svg_path, jpg_path)
            success_count += 1
        except Exception as e:
            print(f"  ERROR converting {svg_path.name}: {e}", file=sys.stderr)
    
    print(f"\nDone! {success_count} of {len(svg_files)} files converted successfully.")

if __name__ == "__main__":
    main()
