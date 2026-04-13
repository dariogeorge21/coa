# Snake Game – Code Guide

This guide walks through every section of `snake.rb` — a RISC-V assembly Snake game — explaining what each instruction does and why it is there.

---

## File Header and Register Map

```asm
.text
.globl main
```

- `.text` tells the assembler this is executable code (not data).
- `.globl main` makes the `main` label visible to the linker so the simulator knows where to start execution.

```
# t0,t1 = head x,y
# s0,s1 = food x,y
# s2 = score
# s3 = score pixels already drawn
# s5 = length
# s6 = grew-this-move flag (1 when length increased)
# s9 = tail write index (circular buffer head pointer)
# Buffer at 0x10010000, each entry = 8 bytes (x word + y word), max 20 entries
```

These comments are the **register convention** for the whole program. In RISC-V:
- `t` registers are **temporaries** – they can be overwritten freely inside a function call.
- `s` registers are **saved** – their values survive across function calls (the callee must restore them). Using `s` registers for the main game state means their values are preserved when the `save_tail` subroutine is called.

---

## 1. Initialization (`main`)

```asm
main:
    li t0, 3          # head X = 3
    li t1, 3          # head Y = 3

    li s0, 8          # food X = 8
    li s1, 8          # food Y = 8

    li s2, 0          # score = 0
    li s3, 0          # score pixels drawn = 0
    li s5, 1          # snake length = 1
    li s6, 0          # grew flag = 0
    li s9, 0          # tail buffer write index = 0
```

`li` (Load Immediate) loads a constant integer directly into a register. All game variables are set to their starting values.

---

### Clear the Tail Buffer

```asm
    li t2, 0x10010000  # t2 = pointer to buffer start
    li t3, 0           # value to store (zero)
    li t4, 40          # loop counter (20 entries × 2 words = 40 words)
clear_buf:
    sw t3, 0(t2)       # store 0 at address t2
    addi t2, t2, 4     # advance pointer by 4 bytes (one word)
    addi t4, t4, -1    # decrement loop counter
    bnez t4, clear_buf # if counter != 0, repeat
```

The tail buffer holds at most 20 (x, y) pairs. Each pair = 2 words × 4 bytes = 8 bytes. 20 entries = 40 words total. This loop writes `0` to every word so stale data from a previous run cannot confuse the game.

`sw` = **Store Word**: writes a 32-bit value from a register to memory.  
`addi` = **Add Immediate**: adds a small constant to a register.  
`bnez` = **Branch if Not Equal to Zero**: loops back if `t4` is not zero yet.

---

### Store the Initial Head into the Buffer

```asm
    li t2, 0x10010000
    sw t0, 0(t2)        # buffer[0].x = 3
    sw t1, 4(t2)        # buffer[0].y = 3
```

Before the game loop starts, the snake's starting position is written to index 0 of the buffer so the tail-erasure logic has a valid entry to read on the very first move.

---

### Clear the Display

```asm
    li t2, 0xf0000000  # t2 = start of display memory
    li t3, 0
    li t4, 100         # 10 × 10 = 100 pixels
init_clear_loop:
    sw t3, 0(t2)
    addi t2, t2, 4
    addi t4, t4, -1
    bnez t4, init_clear_loop
```

The bitmap display is 10 × 10 pixels = 100 cells, each 4 bytes wide. Writing zero (black) to every cell resets the screen.

---

### Draw the Initial Food

```asm
    li t2, 0xf0000000
    li t3, 10
    mul t5, s1, t3     # t5 = food_y × 10
    add t5, t5, s0     # t5 = food_y × 10 + food_x  (= pixel index)
    slli t5, t5, 2     # t5 = pixel_index × 4        (= byte offset)
    add t2, t2, t5     # t2 = display base + byte offset
    li t3, 0xFFFFFF00  # yellow (ARGB: A=FF R=FF G=FF B=00)
    sw t3, 0(t2)       # write yellow to food cell
```

**Pixel address formula:**
```
address = 0xF0000000 + (y × 10 + x) × 4
```

`mul` multiplies two registers.  
`slli` = **Shift Left Logical Immediate**: multiplying by 4 is the same as shifting left by 2 bits, which is slightly faster.

---

### Draw the Initial Head

```asm
    li t2, 0xf0000000
    li t3, 10
    mul t5, t1, t3     # t5 = head_y × 10
    add t5, t5, t0     # t5 = head_y × 10 + head_x
    slli t5, t5, 2     # × 4 → byte offset
    add t2, t2, t5
    li t3, 0xFF00FF00  # green (ARGB: A=FF R=00 G=FF B=00)
    sw t3, 0(t2)
```

Same address calculation as for food, but using head coordinates and a green color.

---

## 2. Input Polling (`wait_input`)

```asm
wait_input:
    li t4, 1

    li t2, 0xf0000190
    lw t3, 0(t2)
    beq t3, t4, do_up

    li t2, 0xf0000194
    lw t3, 0(t2)
    beq t3, t4, do_down

    li t2, 0xf0000198
    lw t3, 0(t2)
    beq t3, t4, do_left

    li t2, 0xf000019c
    lw t3, 0(t2)
    beq t3, t4, do_right

    j wait_input
```

The simulator maps each arrow key to a memory address. When the key is held down, reading that address returns `1`; otherwise it returns `0`.

`lw` = **Load Word**: reads 32 bits from memory into a register.  
`beq` = **Branch if Equal**: jumps to the label if both operands are equal.  
`j` = **Jump**: unconditional branch; loops back to `wait_input` if no key is pressed.

The four keyboard addresses are:

| Address | Key |
|---------|-----|
| `0xF0000190` | UP |
| `0xF0000194` | DOWN |
| `0xF0000198` | LEFT |
| `0xF000019C` | RIGHT |

---

## 3. Movement (`do_up` / `do_down` / `do_left` / `do_right`)

```asm
do_up:
    jal save_tail      # call subroutine to record current position
    addi t1, t1, -1    # Y decreases going up (row 0 is top)
    j check_food

do_down:
    jal save_tail
    addi t1, t1, 1     # Y increases going down
    j check_food

do_left:
    jal save_tail
    addi t0, t0, -1    # X decreases going left
    j check_food

do_right:
    jal save_tail
    addi t0, t0, 1     # X increases going right
    j check_food
```

`jal` = **Jump and Link**: calls a subroutine and stores the return address in `ra` (return-address register).

Before moving the head, the **current** head position is saved to the buffer. This ensures the buffer always contains the positions the body occupies *before* this step.

---

## 4. Saving the Tail (`save_tail`)

```asm
save_tail:
    li t2, 0x10010000  # base of tail buffer
    li t3, 8
    mul t3, s9, t3     # byte_offset = index × 8 (each entry = 8 bytes)
    add t2, t2, t3     # t2 = address of buffer[s9]
    sw t0, 0(t2)       # buffer[s9].x = head_x
    sw t1, 4(t2)       # buffer[s9].y = head_y

    addi s9, s9, 1     # advance write index
    li t3, 20
    blt s9, t3, save_tail_done  # if s9 < 20, no wrap needed
    li s9, 0           # wrap around to 0

save_tail_done:
    ret                # return to caller (jump to address in ra)
```

This is a **circular buffer** — a fixed-size array treated as if it wraps around at the end. The write index `s9` advances by 1 each move and resets to 0 when it reaches 20.

`blt` = **Branch if Less Than**: jumps if the first operand is less than the second.  
`ret` is an alias for `jalr zero, ra, 0` — jumps to the address stored in `ra`.

Why a circular buffer? The snake's body is a sliding window of recent positions. The window moves forward each step. A circular buffer lets us implement this efficiently without shifting array elements.

---

## 5. Food Check (`check_food`)

```asm
check_food:
    li s6, 0           # reset grew flag
    bne t0, s0, draw   # if head_x ≠ food_x, skip to draw
    bne t1, s1, draw   # if head_y ≠ food_y, skip to draw
```

`bne` = **Branch if Not Equal**: jumps if the two registers differ. If either coordinate does not match the food position, the snake has not eaten and we go straight to drawing.

### Food Eaten

```asm
ate_food:
    addi s2, s2, 1     # score++

    li t6, 20
    blt s5, t6, grow   # if length < 20, grow the snake
    j move_food        # already at max length; just move food

grow:
    addi s5, s5, 1     # length++
    li s6, 1           # set grew flag (do NOT erase tail this move)

move_food:
    li t6, 1
    beq s0, t6, food2  # if food_x == 1, switch to position B

    li s0, 1           # food → position A (1, 1)
    li s1, 1
    j draw

food2:
    li s0, 8           # food → position B (8, 8)
    li s1, 8
```

When `s6 = 1`, the tail-erasure step later is skipped, making the snake appear one cell longer.

The `move_food` logic checks the **current** food X position to decide which alternate position to use next. This creates a simple toggle between `(1, 1)` and `(8, 8)`.

---

## 6. Boundary Clamping (`draw` section)

```asm
draw:
    blt t0, zero, fix_x0  # if head_x < 0, clamp to 0
    li t5, 9
    bgt t0, t5, fix_x9    # if head_x > 9, clamp to 9
    j clamp_y

fix_x0: li t0, 0 ; j clamp_y
fix_x9: li t0, 9

clamp_y:
    blt t1, zero, fix_y0  # if head_y < 0, clamp to 0
    li t5, 9
    bgt t1, t5, fix_y9    # if head_y > 9, clamp to 9
    j update_screen

fix_y0: li t1, 0 ; j update_screen
fix_y9: li t1, 9
```

`bgt` = **Branch if Greater Than**.

Instead of ending the game at the wall, the position is simply clamped to the grid boundary.  This makes wall-hitting non-fatal.

---

## 7. Updating the Display (`update_screen`)

### Erasing the Old Tail Cell

```asm
update_screen:
    bnez s6, draw_food     # if snake grew, skip erase

    sub t3, s9, s5         # erase_index = write_index - length
    bge t3, zero, erase_idx_ok
    addi t3, t3, 20        # if negative, wrap by adding 20

erase_idx_ok:
    li t2, 0x10010000
    li t4, 8
    mul t4, t3, t4         # byte_offset = erase_index × 8
    add t2, t2, t4
    lw t4, 0(t2)           # load tail_x from buffer
    lw t5, 4(t2)           # load tail_y from buffer

    li t2, 0xf0000000
    li t3, 10
    mul t3, t5, t3         # tail_y × 10
    add t3, t3, t4         # + tail_x
    slli t3, t3, 2         # × 4 → byte offset
    add t2, t2, t3
    sw zero, 0(t2)         # write black (erase the cell)
```

**How the erase index is computed:**

```
erase_index = (s9 - s5 + 20) mod 20
```

- `s9` is the **next write position** (one slot ahead of the most recently saved position).
- `s5` is the **snake length**.
- Subtracting the length from the write index gives the index of the slot that is now beyond the snake's body and must be cleared.
- The `+ 20` wraps negative values.

`bge` = **Branch if Greater than or Equal**.  
`sub` = subtracts one register from another.

---

### Drawing Food

```asm
draw_food:
    li t2, 0xf0000000
    li t3, 10
    mul t5, s1, t3
    add t5, t5, s0
    slli t5, t5, 2
    add t2, t2, t5
    li t3, 0xFFFFFF00     # yellow
    sw t3, 0(t2)
```

Redraws food every frame because the erase step above might have accidentally cleared it if the head landed on the food cell.

---

### Drawing the Head

```asm
draw_head:
    li t2, 0xf0000000
    li t3, 10
    mul t5, t1, t3
    add t5, t5, t0
    slli t5, t5, 2
    add t2, t2, t5
    li t3, 0xFF0000FF     # blue
    sw t3, 0(t2)
```

Same address formula as food, using head coordinates. Color `0xFF0000FF` = ARGB blue.

---

## 8. Score Display (`score_loop`)

```asm
    beq s3, s2, wait_release  # if all score pixels drawn, skip

score_loop:
    beq s3, s2, wait_release  # exit when caught up

    li t2, 0xf0000000
    li t3, 10
    li t4, 9              # row 9 (bottom row)
    mul t5, t4, t3        # row_offset = 9 × 10
    add t5, t5, s3        # column = s3 (current score pixel to draw)
    slli t5, t5, 2
    add t2, t2, t5
    li t3, 0xFF0000FF     # blue
    sw t3, 0(t2)

    addi s3, s3, 1        # s3++ (one more pixel drawn)
    j score_loop
```

`s3` tracks how many score pixels have been drawn. `s2` is the actual score. The loop draws blue pixels in row 9, columns `0` through `s2 - 1`, one per iteration, catching up whenever the score has increased.

---

## 9. Waiting for Key Release (`wait_release`)

```asm
wait_release:
    li t4, 1

release_loop:
    li t2, 0xf0000190
    lw t3, 0(t2)
    beq t3, t4, release_loop  # still held UP → keep waiting

    li t2, 0xf0000194
    lw t3, 0(t2)
    beq t3, t4, release_loop  # still held DOWN

    li t2, 0xf0000198
    lw t3, 0(t2)
    beq t3, t4, release_loop  # still held LEFT

    li t2, 0xf000019c
    lw t3, 0(t2)
    beq t3, t4, release_loop  # still held RIGHT

    j wait_input              # all keys released → wait for next press
```

Without this step, holding a key would process many moves per second (busy-loop speed). Waiting for release ensures **one move per key press**.

---

## Data Structures Summary

### Circular Buffer (Tail)

```
Address 0x10010000:
┌──────────────┬──────────────┐
│  entry[0].x  │  entry[0].y  │   ← 8 bytes
├──────────────┼──────────────┤
│  entry[1].x  │  entry[1].y  │
├──────────────┼──────────────┤
│     ...      │     ...      │
├──────────────┼──────────────┤
│  entry[19].x │  entry[19].y │
└──────────────┴──────────────┘
```

- Write pointer: `s9` (0–19, wraps around)
- Capacity: 20 entries

On each move:
1. **Write** current head at `buffer[s9]`, then increment `s9`.
2. **Read** erase candidate at `buffer[(s9 - s5 + 20) % 20]`.

### Bitmap Display

```
Address 0xF0000000:
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│(0,0)│(1,0)│(2,0)│(3,0)│(4,0)│(5,0)│(6,0)│(7,0)│(8,0)│(9,0)│  ← row 0
├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│(0,1)│ ... │     │     │     │     │     │     │     │(9,1)│  ← row 1
│ ... │     │     │     │     │     │     │     │     │ ... │
├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│(0,9)│(1,9)│(2,9)│(3,9)│(4,9)│(5,9)│(6,9)│(7,9)│(8,9)│(9,9)│  ← row 9 (score row)
└─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘
```

Each cell = 4 bytes (one ARGB word). Cell address: `0xF0000000 + (y×10 + x)×4`.

---

## Instruction Reference

| Instruction | Full Name | What it does |
|-------------|-----------|--------------|
| `li rd, imm` | Load Immediate | `rd = imm` |
| `lw rd, offset(rs)` | Load Word | `rd = Memory[rs + offset]` |
| `sw rs, offset(rd)` | Store Word | `Memory[rd + offset] = rs` |
| `addi rd, rs, imm` | Add Immediate | `rd = rs + imm` |
| `add rd, rs1, rs2` | Add | `rd = rs1 + rs2` |
| `sub rd, rs1, rs2` | Subtract | `rd = rs1 - rs2` |
| `mul rd, rs1, rs2` | Multiply | `rd = rs1 × rs2` |
| `slli rd, rs, shamt` | Shift Left Logical Imm | `rd = rs << shamt` |
| `beq rs1, rs2, label` | Branch if Equal | Jump if `rs1 == rs2` |
| `bne rs1, rs2, label` | Branch if Not Equal | Jump if `rs1 != rs2` |
| `blt rs1, rs2, label` | Branch if Less Than | Jump if `rs1 < rs2` (signed) |
| `bge rs1, rs2, label` | Branch if ≥ | Jump if `rs1 >= rs2` (signed) |
| `bgt rs1, rs2, label` | Branch if Greater Than | Pseudo; expands to `blt rs2, rs1` |
| `bnez rs, label` | Branch if ≠ Zero | Jump if `rs != 0` |
| `j label` | Jump | Unconditional jump |
| `jal label` | Jump and Link | Call subroutine; save return addr in `ra` |
| `ret` | Return | Jump to address in `ra` |

---

## Control Flow Diagram

```
main
 ├─ clear_buf        (initialization loop)
 ├─ init_clear_loop  (display clear loop)
 ├─ wait_input ──────────────────────────────────────┐
 │   ├─ do_up / do_down / do_left / do_right          │
 │   │   └─ save_tail (subroutine call via jal)       │
 │   ├─ check_food                                    │
 │   │   ├─ ate_food → grow → move_food               │
 │   ├─ draw (clamp X)                                │
 │   │   └─ clamp_y                                   │
 │   ├─ update_screen → erase_idx_ok                  │
 │   ├─ draw_food                                     │
 │   ├─ draw_head                                     │
 │   ├─ score_loop                                    │
 │   └─ wait_release → release_loop ──────────────────┘
 └─ (infinite loop — no exit)
```
