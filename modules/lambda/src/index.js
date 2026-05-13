/**
 * SQS-triggered watermark worker.
 *
 * Lifecycle for a single photo (driven by the API):
 *   1. Photographer uploads -> S3 originals/<portfolio>/<file>, photo row
 *      created with status='uploaded'. NO SQS message yet, NO watermark.
 *   2. Photographer publishes the portfolio -> the API enqueues one SQS
 *      message per uploaded photo and bumps the row to status='processing'.
 *   3. This Lambda reads the message, downloads the original from S3, BAKES
 *      a big red diagonal "WATERMARK" label into the pixels, writes:
 *        - watermarked/<portfolio>/<file>  (full-size with the watermark)
 *        - thumbnails/<portfolio>/<file>   (~600px wide, also watermarked)
 *      and updates the row to status='ready'.
 *   4. After purchase, the API serves a presigned GET on the original key
 *      (untouched, no watermark) so the client can download the clean image.
 *
 * The watermark is rasterized into the JPEG/PNG output, not overlaid in the
 * browser, so a client cannot bypass it by inspecting CSS / DOM.
 */
const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const { Client } = require("pg");
const Jimp = require("jimp");
const { emitEmfCount } = require("./metrics");

const s3 = new S3Client({});

// Resolution caps for the two derived variants. The original file in S3 is
// untouched (only handed out to a client AFTER they purchase), so these caps
// apply ONLY to what the client browser ever sees:
//   - WATERMARKED_MAX_SIDE: the "preview" variant the client uses to pick
//     photos from the gallery. Big enough to inspect detail, small enough that
//     a screenshot is clearly worse than the purchased original.
//   - THUMBNAIL_WIDTH: the gallery card / cart row.
// Both variants ALSO get the rasterized "WATERMARK" label (the thumbnail is
// derived from the already-watermarked image, so there is no clean variant
// anywhere outside the originals/ prefix).
const WATERMARKED_MAX_SIDE = 1280;
const THUMBNAIL_WIDTH = 600;

async function withDbClient(fn) {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.warn("DATABASE_URL not set; skipping photo status update");
    return null;
  }
  const client = new Client({ connectionString: url });
  await client.connect();
  try {
    return await fn(client);
  } finally {
    await client.end().catch(() => {});
  }
}

async function markPhotoReady(client, photoId, watermarkedKey, thumbnailKey) {
  if (!client || !photoId) return;
  await client.query(
    `UPDATE photos
        SET watermarked_url = $2,
            thumbnail_url   = $3,
            status          = 'ready'
      WHERE id = $1`,
    [photoId, watermarkedKey, thumbnailKey],
  );
}

async function markPhotoFailed(client, photoId) {
  if (!client || !photoId) return;
  try {
    await client.query(
      `UPDATE photos SET status = 'failed' WHERE id = $1 AND status <> 'ready'`,
      [photoId],
    );
  } catch (err) {
    console.error("Failed to mark photo as failed", err);
  }
}

// Stream-to-buffer helper (S3 GetObject returns a Node Readable in Lambda).
async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks);
}

/**
 * Bake a red diagonal "WATERMARK" label into the image and return the JPEG buffer.
 *
 * The text is drawn with Jimp's largest built-in white SANS font onto a separate
 * transparent layer, retinted to red pixel-by-pixel (Jimp ships only black/white
 * font glyphs out of the box), rotated -30deg, then composited onto the source.
 * Doing it on a separate layer keeps the rotation cheap (we only rotate text-sized
 * pixels) and avoids transforming the underlying photo.
 */
async function applyWatermark(image) {
  // Downscale BEFORE drawing the watermark so the text label scales with the
  // reduced canvas; otherwise the label would shrink to whatever fraction of
  // the smaller image it lands on. Aspect ratio is preserved.
  const longestSide = Math.max(image.bitmap.width, image.bitmap.height);
  if (longestSide > WATERMARKED_MAX_SIDE) {
    if (image.bitmap.width >= image.bitmap.height) {
      image.resize(WATERMARKED_MAX_SIDE, Jimp.AUTO);
    } else {
      image.resize(Jimp.AUTO, WATERMARKED_MAX_SIDE);
    }
  }
  const w = image.bitmap.width;
  const h = image.bitmap.height;
  const font = await Jimp.loadFont(Jimp.FONT_SANS_128_WHITE);
  const text = "WATERMARK";

  const textWidth = Jimp.measureText(font, text);
  const textHeight = Jimp.measureTextHeight(font, text, textWidth);

  // Layer is sized to fit the text comfortably; padding avoids clipping after rotation.
  const layerW = textWidth + 80;
  const layerH = textHeight + 80;
  const layer = new Jimp(layerW, layerH, 0x00000000);
  layer.print(font, 40, 40, text);

  // Recolor every visible pixel to opaque red (the SANS_128_WHITE font is white).
  layer.scan(0, 0, layer.bitmap.width, layer.bitmap.height, function recolor(_x, _y, idx) {
    const alpha = this.bitmap.data[idx + 3];
    if (alpha > 0) {
      this.bitmap.data[idx] = 220; // R
      this.bitmap.data[idx + 1] = 30; // G
      this.bitmap.data[idx + 2] = 30; // B
      this.bitmap.data[idx + 3] = 220; // A — slightly translucent so the photo bleeds through
    }
  });

  // Resize the watermark so it spans roughly 75% of the image's longest side.
  const targetTextWidth = Math.max(w, h) * 0.75;
  const scale = targetTextWidth / layer.bitmap.width;
  if (scale > 0 && Number.isFinite(scale) && Math.abs(scale - 1) > 0.01) {
    layer.resize(Math.round(layer.bitmap.width * scale), Jimp.AUTO);
  }

  // Diagonal: rotate the text layer; `false` keeps the bitmap dimensions
  // (we already padded above so the rotated glyphs do not get clipped).
  layer.rotate(-30, false);

  const cx = Math.round((w - layer.bitmap.width) / 2);
  const cy = Math.round((h - layer.bitmap.height) / 2);
  image.composite(layer, cx, cy, {
    mode: Jimp.BLEND_SOURCE_OVER,
    opacitySource: 1,
    opacityDest: 1,
  });

  return image.quality(85).getBufferAsync(Jimp.MIME_JPEG);
}

async function buildThumbnail(originalImage) {
  // Clone so we don't disturb the full-size watermark image we're about to upload.
  const thumb = originalImage.clone();
  if (thumb.bitmap.width > THUMBNAIL_WIDTH) {
    thumb.resize(THUMBNAIL_WIDTH, Jimp.AUTO);
  }
  return thumb.quality(80).getBufferAsync(Jimp.MIME_JPEG);
}

async function processOne(bucket, srcBucket, key) {
  const wmKey = key.replace(/^originals\//, "watermarked/");
  const thKey = key.replace(/^originals\//, "thumbnails/");

  const obj = await s3.send(new GetObjectCommand({ Bucket: srcBucket, Key: key }));
  const buf = await streamToBuffer(obj.Body);

  // Decode once, watermark once, then derive the thumbnail from the watermarked image.
  const image = await Jimp.read(buf);
  const watermarkedBuf = await applyWatermark(image);
  // applyWatermark mutates `image`, so a clone of the watermarked version is the thumb source.
  const watermarkedImage = await Jimp.read(watermarkedBuf);
  const thumbBuf = await buildThumbnail(watermarkedImage);

  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: wmKey,
      Body: watermarkedBuf,
      ContentType: "image/jpeg",
    }),
  );
  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: thKey,
      Body: thumbBuf,
      ContentType: "image/jpeg",
    }),
  );

  return { wmKey, thKey };
}

exports.handler = async (event) => {
  const bucket = process.env.S3_BUCKET;
  if (!bucket) {
    throw new Error("S3_BUCKET is not set");
  }

  await withDbClient(async (db) => {
    for (const record of event.Records || []) {
      let body;
      try {
        body = JSON.parse(record.body);
      } catch {
        console.warn("Non-JSON message, skipping");
        continue;
      }
      const key = body.key;
      const photoId = body.photoId;
      const srcBucket = body.bucket || bucket;
      if (!key) continue;

      try {
        console.log("watermark start", { key, photoId });
        const { wmKey, thKey } = await processOne(bucket, srcBucket, key);
        await markPhotoReady(db, photoId, wmKey, thKey);
        console.log("watermark done", { key, photoId });
        try {
          emitEmfCount({ WatermarkSuccessCount: 1 }, { Service: "watermark" });
        } catch {
          /* no afectar el flujo principal */
        }
      } catch (err) {
        console.error("watermark pipeline error", { key, photoId, err });
        await markPhotoFailed(db, photoId);
        throw err;
      }
    }
  });
};
