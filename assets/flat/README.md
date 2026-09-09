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
