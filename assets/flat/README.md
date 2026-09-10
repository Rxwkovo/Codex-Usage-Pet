# Hand-drawn-style raster artwork

Generated with the built-in imagegen tool on 2026-09-10 from the user's approved flat cartoon character. These are AI-generated hand-drawn-style images, not illustrations drawn by a human artist or Canva exports.

Seven original PNG sheets, four columns and two rows each: walk, sit, sleep, stretch, wave, compact, moods. The originals have a white paper background. The player keys the matte at load time, removes detached marks, anchors each frame to the feet, and keeps the first-cell scale throughout each action. No character geometry is drawn by the runtime.

Prompt set:

Common: Same mint sprout code mascot, flat 2D cartoon cel, gently imperfect dark forest-green hand-ink outlines, pale mint fills, dark screen face, rosy cheeks, stubby hands/feet, tiny belly code symbol. Four columns and two rows, eight chronological drawings, equal cells, white background, no panels/captions/checkerboard, no 3D or highlights; consistent body, camera and scale, ground baseline at 85 percent, full figure roughly 70 percent of cell height.

- Walk: alternating foot contact, down, passing and up poses, counter-swinging arms and following leaves. The generated lower row faces the other way; the player mirrors that row to keep a common walking direction.
- Sit: standing, bending knees, feet forward, lowering rear, landing, settling, seated relaxed. Keep body intact and feet in front.
- Sleep: standing, bending, sitting, hand supporting the lean, lowering onto side, tucking feet, closed eyes, peaceful rest.
- Stretch: neutral, anticipation, arms up, full stretch, gentle side lean, lowering arms, relax, neutral.
- Wave: neutral, arm lifting, wrist inward, outward, inward, outward, lowering, neutral.
- Compact: neutral, arms folding, feet drawing in, compact sitting, hands tucking, feet tucked, round body, content tucked ball.
- Moods: top row neutral / happy / worried / exhausted; bottom row corresponding closed-eye faces. Same standing body in all cells.

Drawn frames play as clear animation cels; a short configurable dissolve joins different actions. Long adjacent-frame dissolves are deliberately avoided because they produce doubled eyes and outlines. Small line variations remain part of the generated art. Quota expressions and blinks apply while standing idle; resting and gesturing use their drawn expressions and return to the current quota expression when finished.


## v2.1 additions (2026-09-11)

Wave and stretch now use four-column, four-row sheets (16 complete cels). Other motion sheets retain eight cels. `action-moods.png` and `action-blinks.png` contain four mood columns (happy, calm, worried, exhausted) and six action rows (walk, sit, sleep, stretch, rejected compact row, wave). The incorrect compact row is unused; `compact-moods.png` supplies four moods and their closed-eye counterparts in two rows. The player maps drawn screen pixels to each full-body cel, without a limb rig. Face-only results are cached; blinking does not crossfade the whole body.

Generation prompts: preserve the approved mint mascot's complete silhouette, flat paper texture, dark outlines, two sprout leaves, face screen and belly code mark. Draw 16 chronological gesture cels with gradual anticipation, raised hands, peak pose and settling; separately draw each action's four quota emotions and corresponding closed eyelids. Compact must remain a tucked round ball with no visible feet. All inputs were original approved artwork. White background is keyed only around the silhouette, keeping enclosed highlights opaque.

These additions supersede the old statement above that expressions apply only in standing idle. Runtime checks cover all 576 full-body-frame / mood / blink combinations. Only wave and stretch gain body frames in this release.


## v2.1.1 rendering fix

Original PNGs remain unchanged. Panel detection now isolates the thick face core before filling its convex boundary, preventing a touching body outline in the sleep cels from becoming part of the face. The backing buffer is 440×420 while the logical pet stays 220×210, with high-quality raster scaling and a 48-entry composition cache. `PixelWidth` / `PixelHeight` describe the buffer returned by `GetPixels()`.
