# Snake Game – Working Process

## What Is This Project?

This project is a **Snake game** written entirely in **RISC-V assembly language**. It is designed to run inside a RISC-V simulator (such as RARS) that provides:

- A **10 × 10 bitmap display** mapped to memory.
- **Memory-mapped keyboard input** so the program can read arrow-key presses.
- A **data memory region** for the snake's body (tail) storage.

---

## Hardware / Simulator Environment

| Component | Address | Details |
|-----------|---------|---------|
| Bitmap display | `0xF0000000` | 10 × 10 grid; each pixel = 4 bytes (ARGB color word) |
| Key – UP | `0xF0000190` | Reads `1` when the UP arrow is held, `0` otherwise |
| Key – DOWN | `0xF0000194` | Reads `1` when DOWN is held |
| Key – LEFT | `0xF0000198` | Reads `1` when LEFT is held |
| Key – RIGHT | `0xF000019C` | Reads `1` when RIGHT is held |
| Tail buffer | `0x10010000` | Holds up to 20 (x, y) positions, 8 bytes each |

### Pixel Address Formula

To write a color to grid cell `(x, y)`:

```
pixel_address = 0xF0000000 + (y × 10 + x) × 4
```

The display is row-major: row 0 is at the top, row 9 is at the bottom.

### Color Values (ARGB format)

| Color | Hex value | Used for |
|-------|-----------|---------|
| Yellow | `0xFFFFFF00` | Food |
| Green | `0xFF00FF00` | Initial head (startup only) |
| Blue | `0xFF0000FF` | Head (every move) and score pixels |
| Black / 0 | `0x00000000` | Empty cell (erase) |

---

## Game Variables (Registers)

| Register | Role |
|----------|------|
| `t0` | Head X position (column, 0–9) |
| `t1` | Head Y position (row, 0–9) |
| `s0` | Food X position |
| `s1` | Food Y position |
| `s2` | Current score (count of food eaten) |
| `s3` | Score pixels already drawn on screen |
| `s5` | Current snake length (starts at 1, max 20) |
| `s6` | "Grew this move" flag: `1` = snake just grew |
| `s9` | Write index into the circular tail buffer |

---

## Game Concepts

### The Grid
The playing field is a 10 × 10 cell grid. The snake cannot leave this area; if it tries, its position is **clamped** to the nearest edge cell (it does not die on collision in this implementation).

### The Snake Body (Circular Buffer)
The snake's history of positions is stored in a circular buffer at `0x10010000`. It holds up to **20 entries**, each 8 bytes (one 4-byte word for X, one for Y). Every time the snake moves, the current head position is written into this buffer before the head advances. When the snake should erase its tail (it did not eat food), the oldest entry in the buffer is read and that cell is cleared on the display.

### Food
Food spawns at one of two fixed positions:
- Position A: `(8, 8)`
- Position B: `(1, 1)`

It alternates between these two positions every time it is eaten.

### Score
The score equals the number of food items eaten. The score is visualized as a row of **blue pixels on the bottom row (row 9)** of the display, starting from the left. Each new point lights up one more cell.

---

## Complete Game Loop

```
            ┌─────────────────────────────────────────┐
            │              INITIALIZATION              │
            │  • Set head to (3, 3)                   │
            │  • Set food to (8, 8)                   │
            │  • Zero all registers and tail buffer   │
            │  • Clear the entire display             │
            │  • Draw food (yellow) at (8, 8)         │
            │  • Draw head (green) at (3, 3)          │
            └──────────────────┬──────────────────────┘
                               │
            ┌──────────────────▼──────────────────────┐
            │            WAIT FOR INPUT               │◄──────────────────────┐
            │  Poll keyboard addresses in a loop      │                       │
            │  until one of the four keys reads 1     │                       │
            └──────────────────┬──────────────────────┘                       │
                               │ key pressed                                  │
            ┌──────────────────▼──────────────────────┐                       │
            │              SAVE TAIL                  │                       │
            │  Write current head (t0, t1) into       │                       │
            │  circular buffer at index s9            │                       │
            │  Advance s9 (wraps at 20)               │                       │
            └──────────────────┬──────────────────────┘                       │
                               │                                              │
            ┌──────────────────▼──────────────────────┐                       │
            │                 MOVE                    │                       │
            │  Update t0 or t1 based on direction     │                       │
            └──────────────────┬──────────────────────┘                       │
                               │                                              │
            ┌──────────────────▼──────────────────────┐                       │
            │             CHECK FOOD                  │                       │
            │  Does (t0, t1) == (s0, s1)?             │                       │
            │  YES → increment score, grow snake,     │                       │
            │         move food to next position      │                       │
            │  NO  → continue to DRAW                 │                       │
            └──────────────────┬──────────────────────┘                       │
                               │                                              │
            ┌──────────────────▼──────────────────────┐                       │
            │            CLAMP POSITION               │                       │
            │  If x < 0 → x = 0                       │                       │
            │  If x > 9 → x = 9                       │                       │
            │  If y < 0 → y = 0                       │                       │
            │  If y > 9 → y = 9                       │                       │
            └──────────────────┬──────────────────────┘                       │
                               │                                              │
            ┌──────────────────▼──────────────────────┐                       │
            │           UPDATE DISPLAY                │                       │
            │  If snake did NOT grow:                  │                       │
            │    • Compute index of tail to erase     │                       │
            │    • Clear that cell (write 0)          │                       │
            │  Draw food (yellow)                     │                       │
            │  Draw head (blue)                       │                       │
            └──────────────────┬──────────────────────┘                       │
                               │                                              │
            ┌──────────────────▼──────────────────────┐                       │
            │           UPDATE SCORE DISPLAY          │                       │
            │  If s3 < s2: draw more blue pixels      │                       │
            │  in row 9 (bottom) until s3 == s2       │                       │
            └──────────────────┬──────────────────────┘                       │
                               │                                              │
            ┌──────────────────▼──────────────────────┐                       │
            │           WAIT FOR RELEASE              │                       │
            │  Poll all keys until all read 0         │───────────────────────┘
            └─────────────────────────────────────────┘
```

---

## Step-by-Step Walkthrough of a Single Move

Assume the snake's head is at `(3, 3)` and the player presses **RIGHT**.

1. **Save tail**: The position `(3, 3)` is written to the circular buffer at index `s9`. The index is then advanced to `s9 + 1`.

2. **Move**: `t0` (X) is incremented to `4`. The head is now at `(4, 3)`.

3. **Check food**: `(4, 3)` is compared with the food position `(8, 8)`. They differ, so `s6` stays `0` (no growth).

4. **Clamp**: `4` and `3` are both within `[0, 9]`, so no clamping needed.

5. **Erase tail**: Since `s6 == 0` (snake did not grow), compute the buffer index of the cell that should leave the body:
   ```
   erase_index = s9 - s5        (s9 = 1, s5 = 1  →  erase_index = 0)
   ```
   If negative, add 20 (wrap). Read `(x, y)` from buffer index 0, which holds `(3, 3)`. Write black (`0`) to display cell `(3, 3)`.

6. **Draw food**: Write yellow (`0xFFFFFF00`) to display cell `(8, 8)`.

7. **Draw head**: Write blue (`0xFF0000FF`) to display cell `(4, 3)`.

8. **Score display**: `s3 == s2` (both 0), nothing to draw.

9. **Wait release**: Loop until the RIGHT key reads `0`, then go back to **WAIT FOR INPUT**.

---

## Eating Food

When the head lands on the food cell:

1. Score (`s2`) is incremented by 1.
2. If the snake length `s5` is less than 20, `s5` is incremented and the **grew flag** `s6` is set to 1. This prevents the tail from being erased on this move, making the snake visually longer.
3. Food moves to the next fixed position (alternating between `(1, 1)` and `(8, 8)`).

---

## Boundary Behavior

The game does **not** end when the snake hits a wall. Instead the head is **clamped** to the nearest edge. For example, moving left from `x = 0` keeps the head at `x = 0`. This makes wall collisions non-fatal.

---

## Limitations

| Limitation | Reason |
|------------|--------|
| Max snake length: 20 | Fixed-size circular buffer |
| Food only at 2 positions | No random number generation in this implementation |
| No self-collision detection | Not implemented; snake can pass through itself |
| No game-over state | Game loops forever |
