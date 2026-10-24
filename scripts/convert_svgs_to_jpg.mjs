/**
 * Convert all Play Store SVGs to JPG format using sharp.
 * sharp bundles librsvg, so no system Cairo dependency needed.
 */

import sharp from 'sharp';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectDir = path.resolve(__dirname, '..');
const svgDir = path.join(projectDir, 'assets', 'playstore_graphics');
const outputDir = svgDir;

const WIDTH = 1080;
const HEIGHT = 1920;
const JPEG_QUALITY = 92;

async function convertSvgToJpg(svgPath, jpgPath) {
  const svgName = path.basename(svgPath);
  const jpgName = path.basename(jpgPath);
  console.log(`  Converting: ${svgName} -> ${jpgName}`);

  const svgBuffer = fs.readFileSync(svgPath);

  // SVG needs to specify dimensions; if not, sharp may not scale properly.
  // We'll resize explicitly.
  const pngBuffer = await sharp(svgBuffer)
    .resize(WIDTH, HEIGHT, {
      fit: 'fill', // stretch to exact dimensions
      background: { r: 10, g: 10, b: 26, alpha: 1 }, // dark background fallback
    })
    .png()
    .toBuffer();

  // Convert PNG buffer to JPG with white/ dark background for transparency
  await sharp(pngBuffer)
    .flatten({ background: { r: 10, g: 10, b: 26 } }) // remove alpha, set bg
    .jpeg({ quality: JPEG_QUALITY, mozjpeg: true })
    .toFile(jpgPath);

  const stats = fs.statSync(jpgPath);
  const sizeKB = (stats.size / 1024).toFixed(1);
  console.log(`    -> Saved: ${jpgName} (${WIDTH}x${HEIGHT}, ${sizeKB}KB)`);
}

async function main() {
  // Find all SVG files
  const files = fs.readdirSync(svgDir).filter(f => f.endsWith('.svg')).sort();

  if (files.length === 0) {
    console.log(`No SVG files found in ${svgDir}`);
    return;
  }

  console.log(`Found ${files.length} SVG files to convert\n`);

  let successCount = 0;
  for (const file of files) {
    const svgPath = path.join(svgDir, file);
    const jpgName = file.replace(/\.svg$/i, '.jpg');
    const jpgPath = path.join(outputDir, jpgName);

    // Skip if JPG exists and is newer than SVG
    if (fs.existsSync(jpgPath)) {
      const svgMtime = fs.statSync(svgPath).mtimeMs;
      const jpgMtime = fs.statSync(jpgPath).mtimeMs;
      if (jpgMtime > svgMtime) {
        console.log(`  Skipping (up to date): ${jpgName}`);
        continue;
      }
    }

    try {
      await convertSvgToJpg(svgPath, jpgPath);
      successCount++;
    } catch (err) {
      console.error(`  ERROR converting ${file}: ${err.message}`);
    }
  }

  console.log(`\nDone! ${successCount} of ${files.length} files converted successfully.`);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
