.text
.globl main

# t0,t1 = head x,y
# s0,s1 = food x,y
# s2 = score
# s3 = score pixels already drawn
# s5 = length
# s6 = grew-this-move flag (1 when length increased)
# s9 = tail write index (circular buffer head pointer)
# Buffer at 0x10010000, each entry = 8 bytes (x word + y word), max 20 entries

main:
    li t0, 3
    li t1, 3

    li s0, 8
    li s1, 8

    li s2, 0
    li s3, 0
    li s5, 1
    li s6, 0
    li s9, 0

    # clear tail buffer (20 entries * 2 words * 4 bytes = 160 bytes)
    li t2, 0x10010000
    li t3, 0
    li t4, 40
clear_buf:
    sw t3, 0(t2)
    addi t2, t2, 4
    addi t4, t4, -1
    bnez t4, clear_buf

    # store initial head into buffer index 0
    li t2, 0x10010000
    sw t0, 0(t2)
    sw t1, 4(t2)

    # one-time display clear at startup
    li t2, 0xf0000000
    li t3, 0
    li t4, 100
init_clear_loop:
    sw t3, 0(t2)
    addi t2, t2, 4
    addi t4, t4, -1
    bnez t4, init_clear_loop

    # draw initial food (yellow)
    li t2, 0xf0000000
    li t3, 10
    mul t5, s1, t3
    add t5, t5, s0
    slli t5, t5, 2
    add t2, t2, t5
    li t3, 0xFFFFFF00
    sw t3, 0(t2)

    # draw initial head (blue)
    li t2, 0xf0000000
    li t3, 10
    mul t5, t1, t3
    add t5, t5, t0
    slli t5, t5, 2
    add t2, t2, t5
    li t3, 0xFF00FF00
    sw t3, 0(t2)

# -------- INPUT --------
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

# -------- MOVE --------
do_up:
    jal save_tail
    addi t1, t1, -1
    j check_food

do_down:
    jal save_tail
    addi t1, t1, 1
    j check_food

do_left:
    jal save_tail
    addi t0, t0, -1
    j check_food

do_right:
    jal save_tail
    addi t0, t0, 1
    j check_food

# -------- SAVE TAIL --------
# writes current head into circular buffer at index s9, then advances s9
save_tail:
    li t2, 0x10010000
    li t3, 8
    mul t3, s9, t3
    add t2, t2, t3
    sw t0, 0(t2)
    sw t1, 4(t2)

    addi s9, s9, 1
    li t3, 20
    blt s9, t3, save_tail_done
    li s9, 0

save_tail_done:
    ret

# -------- FOOD --------
check_food:
    li s6, 0
    bne t0, s0, draw
    bne t1, s1, draw

ate_food:
    addi s2, s2, 1

    li t6, 20
    blt s5, t6, grow
    j move_food

grow:
    addi s5, s5, 1
    li s6, 1

move_food:
    li t6, 1
    beq s0, t6, food2

    li s0, 1
    li s1, 1
    j draw

food2:
    li s0, 8
    li s1, 8

# -------- DRAW --------
draw:
    # clamp x
    blt t0, zero, fix_x0
    li t5, 9
    bgt t0, t5, fix_x9
    j clamp_y

fix_x0:
    li t0, 0
    j clamp_y

fix_x9:
    li t0, 9

clamp_y:
    blt t1, zero, fix_y0
    li t5, 9
    bgt t1, t5, fix_y9
    j update_screen

fix_y0:
    li t1, 0
    j update_screen

fix_y9:
    li t1, 9

# -------- UPDATE DISPLAY --------
update_screen:
    # If snake did not grow, clear the one cell that leaves the body.
    bnez s6, draw_food
    sub t3, s9, s5
    bge t3, zero, erase_idx_ok
    addi t3, t3, 20
erase_idx_ok:
    li t2, 0x10010000
    li t4, 8
    mul t4, t3, t4
    add t2, t2, t4
    lw t4, 0(t2)
    lw t5, 4(t2)

    li t2, 0xf0000000
    li t3, 10
    mul t3, t5, t3
    add t3, t3, t4
    slli t3, t3, 2
    add t2, t2, t3
    sw zero, 0(t2)

# -------- DRAW FOOD --------
draw_food:
    li t2, 0xf0000000
    li t3, 10
    mul t5, s1, t3
    add t5, t5, s0
    slli t5, t5, 2
    add t2, t2, t5
    li t3, 0xFFFFFF00
    sw t3, 0(t2)

# -------- DRAW HEAD --------
draw_head:
    li t2, 0xf0000000
    li t3, 10
    mul t5, t1, t3
    add t5, t5, t0
    slli t5, t5, 2
    add t2, t2, t5
    li t3, 0xFF0000FF
    sw t3, 0(t2)

# -------- SCORE UPDATE --------
    beq s3, s2, wait_release

score_loop:
    beq s3, s2, wait_release

    li t2, 0xf0000000
    li t3, 10
    li t4, 9
    mul t5, t4, t3
    add t5, t5, s3
    slli t5, t5, 2
    add t2, t2, t5
    li t3, 0xFF0000FF
    sw t3, 0(t2)

    addi s3, s3, 1
    j score_loop

# -------- RELEASE --------
wait_release:
    li t4, 1

release_loop:
    li t2, 0xf0000190
    lw t3, 0(t2)
    beq t3, t4, release_loop

    li t2, 0xf0000194
    lw t3, 0(t2)
    beq t3, t4, release_loop

    li t2, 0xf0000198
    lw t3, 0(t2)
    beq t3, t4, release_loop

    li t2, 0xf000019c
    lw t3, 0(t2)
    beq t3, t4, release_loop

    j wait_input
