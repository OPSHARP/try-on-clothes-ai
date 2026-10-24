#!/usr/bin/env python3
"""Test the IDM-VTON Gradio 4.x queue-based API.

This script tests the complete VTON pipeline:
  1. Upload person & garment images as multipart/form-data
  2. Submit to /queue/join with fn_index=2, trigger_id=25
  3. Poll /queue/data?session_hash=xxx for SSE results
  4. Download result image

Usage:
  python scripts/test_vton_api.py

Requirements:
  pip install Pillow
"""

import json
import urllib.request
import urllib.error
import time
import os
import hashlib

# ── Configuration ──────────────────────────────────────────────────────────

API_KEY = os.environ.get("HF_API_KEY", "")
SPACE_URL = "https://yisol-idm-vton.hf.space"

# ── HTTP helper ────────────────────────────────────────────────────────────


def req(url, data=None, method=None, headers_in=None, timeout=120):
    """Make an HTTP request."""
    h = {"Authorization": f"Bearer {API_KEY}"}
    if headers_in:
        h.update(headers_in)

    body_bytes = None
    if data is not None:
        if isinstance(data, (dict, list)):
            body_bytes = json.dumps(data).encode("utf-8")
            if "Content-Type" not in h:
                h["Content-Type"] = "application/json"
        else:
            body_bytes = data

    r = urllib.request.Request(
        url, data=body_bytes,
        method=method or ("POST" if data is not None else "GET"),
        headers=h,
    )
    try:
        resp = urllib.request.urlopen(r, timeout=timeout)
        return (resp.status, dict(resp.headers), resp.read())
    except urllib.error.HTTPError as e:
        return (e.code, dict(e.headers), e.read())
    except Exception as e:
        return (None, {}, str(e).encode("utf-8"))


# ── Image upload ───────────────────────────────────────────────────────────


def upload_image(image_bytes, filename="test.png"):
    """Upload image to Space via /upload (multipart) and return file paths."""
    boundary = "----Boundary" + hashlib.md5(
        str(time.time()).encode()
    ).hexdigest()[:8]

    body_parts = []
    body_parts.append(f"--{boundary}\r\n".encode())
    body_parts.append(
        f'Content-Disposition: form-data; name="files"; '
        f'filename="{filename}"\r\n'.encode()
    )
    body_parts.append(b"Content-Type: image/png\r\n\r\n")
    body_parts.append(image_bytes)
    body_parts.append(f"\r\n--{boundary}--\r\n".encode())

    upload_body = b"".join(body_parts)

    status, headers, body = req(
        f"{SPACE_URL}/upload",
        data=upload_body,
        method="POST",
        headers_in={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        timeout=30,
    )

    if status == 200 and body:
        return json.loads(body.decode("utf-8"))
    return None


# ── Test image generation ──────────────────────────────────────────────────


def create_test_images():
    """Create realistic-looking test images using PIL."""
    try:
        from PIL import Image, ImageDraw
        import io
    except ImportError:
        print("PIL not installed. Run: pip install Pillow")
        return None, None

    # Create a "person" image (torso-shaped figure)
    person = Image.new("RGB", (512, 512), (200, 200, 200))
    draw = ImageDraw.Draw(person)

    # Head (circle)
    draw.ellipse([180, 20, 332, 180], fill=(255, 200, 180))

    # Neck
    draw.rectangle([235, 180, 277, 220], fill=(255, 200, 180))

    # Body/torso
    draw.polygon(
        [(200, 220), (312, 220), (340, 420), (172, 420)], fill=(100, 120, 200)
    )

    # Left arm
    draw.polygon(
        [(172, 240), (200, 240), (160, 420), (132, 420)], fill=(100, 120, 200)
    )

    # Right arm
    draw.polygon(
        [(312, 240), (340, 240), (380, 420), (352, 420)], fill=(100, 120, 200)
    )

    # Face features
    draw.ellipse([225, 70, 245, 95], fill=(50, 50, 50))  # left eye
    draw.ellipse([267, 70, 287, 95], fill=(50, 50, 50))  # right eye
    draw.arc([225, 100, 287, 140], 0, 180, fill=(180, 80, 80), width=3)  # mouth

    buf = io.BytesIO()
    person.save(buf, format="PNG")
    person_bytes = buf.getvalue()
    with open("scripts/test_person.png", "wb") as f:
        f.write(person_bytes)

    # Create a "garment" image (t-shirt shape)
    garment = Image.new("RGB", (256, 256), (240, 240, 240))
    draw = ImageDraw.Draw(garment)

    # T-shirt shape
    draw.polygon(
        [(50, 20), (206, 20), (230, 70), (220, 220), (36, 220), (26, 70)],
        fill=(220, 50, 60),
    )

    # Neckline
    draw.arc([90, 0, 166, 50], 0, 180, fill=(240, 240, 240), width=8)

    buf = io.BytesIO()
    garment.save(buf, format="PNG")
    garment_bytes = buf.getvalue()
    with open("scripts/test_garment.png", "wb") as f:
        f.write(garment_bytes)

    return person_bytes, garment_bytes


# ── Main test ──────────────────────────────────────────────────────────────


def test_vton():
    """Run the complete VTON test."""
    print("=" * 60)
    print("VTON API TEST (Gradio 4.x Queue-Based)")
    print("=" * 60)

    # 1. Create test images
    print("\n1. Creating test images...")
    person_img, garment_img = create_test_images()
    if not person_img or not garment_img:
        print("FAILED: Could not create test images")
        return False
    print(f"   Person image: {len(person_img)} bytes")
    print(f"   Garment image: {len(garment_img)} bytes")

    # 2. Upload images
    print("\n2. Uploading person image...")
    person_paths = upload_image(person_img, "person.png")
    if person_paths:
        print(f"   Uploaded: {person_paths}")
    else:
        print("   Upload FAILED!")
        return False

    print("\n3. Uploading garment image...")
    clothes_paths = upload_image(garment_img, "garment.png")
    if clothes_paths:
        print(f"   Uploaded: {clothes_paths}")
    else:
        print("   Upload FAILED!")
        return False

    person_file = (
        person_paths[0]
        if isinstance(person_paths, list)
        else person_paths
    )
    clothes_file = (
        clothes_paths[0]
        if isinstance(clothes_paths, list)
        else clothes_paths
    )

    # 4. Prepare payload matching Gradio 4.x /tryon endpoint
    person_filedata = {
        "path": person_file,
        "meta": {"_type": "gradio.FileData"},
    }
    clothes_filedata = {
        "path": clothes_file,
        "meta": {"_type": "gradio.FileData"},
    }

    session_hash = hashlib.md5(
        str(time.time()).encode()
    ).hexdigest()[:10]

    payload = {
        "data": [
            # Human image (ImageEditor component)
            {
                "background": person_filedata,
                "layers": [],
                "composite": None,
            },
            # Garment image (FileData)
            clothes_filedata,
            # Garment description
            "Upper body garment",
            # Auto-mask checkbox
            True,
            # Crop checkbox
            False,
            # Denoising steps
            30,
            # Seed
            42,
        ],
        "event_data": None,
        "fn_index": 2,
        "trigger_id": 25,
        "session_hash": session_hash,
    }

    # 5. Submit to queue
    print(f"\n4. Submitting to /queue/join...")
    status, headers, body = req(
        f"{SPACE_URL}/queue/join",
        data=payload,
        method="POST",
        timeout=120,
    )
    print(f"   HTTP {status}")

    if status != 200:
        print(f"   Queue submission FAILED: {body.decode('utf-8', errors='replace')[:500]}")
        return False

    result = json.loads(body.decode("utf-8"))
    event_id = result.get("event_id")
    print(f"   event_id: {event_id}")

    if not event_id:
        print("   No event_id in response!")
        return False

    # 6. Poll for results
    print("\n5. Polling for results (may take 30-60s)...")
    sse_url = f"{SPACE_URL}/queue/data?session_hash={session_hash}"

    for i in range(60):  # 60 * 3s = 180s max
        time.sleep(3)
        s, h, b = req(sse_url, method="GET", timeout=60)

        if not b:
            continue

        raw = b.decode("utf-8", errors="replace")
        completed = False

        for line in raw.split("\n"):
            line = line.strip()
            if not line.startswith("data: "):
                continue

            json_str = line[6:]
            try:
                line_data = json.loads(json_str)
            except json.JSONDecodeError:
                continue

            msg = line_data.get("msg", "")

            if msg == "estimation":
                eta = line_data.get("rank_eta", 0)
                print(f"   [{i+1}] ETA: ~{eta:.0f}s")

            elif msg == "process_starts":
                print(f"   [{i+1}] Processing started")

            elif msg == "process_generating":
                progress = line_data.get("progress", {})
                desc = progress.get("desc", "")
                if desc:
                    print(f"   [{i+1}] Generating: {desc[:80]}")

            elif msg == "process_completed":
                completed = True
                output = line_data.get("output", {})

                error = output.get("error")
                if error:
                    print(f"   [{i+1}] MODEL ERROR: {error}")
                    return False

                data_list = output.get("data", [])
                print(f"   [{i+1}] COMPLETED! Got {len(data_list)} outputs")

                for idx, item in enumerate(data_list):
                    if isinstance(item, dict):
                        img_url = item.get("url") or item.get("path", "")
                        if img_url:
                            if not img_url.startswith("http"):
                                img_url = f"{SPACE_URL}/file{img_url}"
                            print(f"   Result {idx}: {img_url}")
                            si, sh, sb = req(img_url, method="GET", timeout=30)
                            print(f"   Download: HTTP {si}, {len(sb)} bytes")
                            fname = f"scripts/vton_result_{idx}.png"
                            with open(fname, "wb") as f:
                                f.write(sb)
                            print(f"   Saved to: {fname}")
                            print(f"\n   *** GENERATION SUCCESSFUL ***")
                            return True
                    elif isinstance(item, str) and item.startswith("data:image"):
                        # Base64-encoded result
                        import base64
                        b64_data = item.split(",")[1]
                        img_bytes = base64.b64decode(b64_data)
                        fname = f"scripts/vton_result_{idx}.png"
                        with open(fname, "wb") as f:
                            f.write(img_bytes)
                        print(f"   Saved base64 result to: {fname}")
                        print(f"\n   *** GENERATION SUCCESSFUL ***")
                        return True

                print(f"   Full output: {json.dumps(output, indent=2)[:2000]}")
                return False

        if completed:
            break

    print("\nFAILED: Did not receive process_completed within timeout")
    return False


if __name__ == "__main__":
    test_vton()
