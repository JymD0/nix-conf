import pytest
from ledmatrix import Matrix, ROWS, COLS

def test_dimensions():
    m = Matrix()
    assert ROWS == 34
    assert COLS == 9
    assert len(m.buf) == ROWS
    assert len(m.buf[0]) == COLS

def test_set_clamps():
    m = Matrix()
    m.set(0, 0, 300)
    assert m.get(0, 0) == 255
    m.set(0, 0, -10)
    assert m.get(0, 0) == 0

def test_set_oob_is_ignored():
    m = Matrix()
    m.set(-1, 0, 255)
    m.set(0, -1, 255)
    m.set(ROWS, 0, 255)
    m.set(0, COLS, 255)

def test_clear():
    m = Matrix()
    m.set(0, 0, 200)
    m.clear()
    assert m.get(0, 0) == 0

def test_fill():
    m = Matrix()
    m.fill(128)
    assert m.get(17, 4) == 128

def test_snake_pos_row0_left_to_right():
    m = Matrix()
    assert m.snake_pos(0) == (0, 0)
    assert m.snake_pos(8) == (0, 8)

def test_snake_pos_row1_right_to_left():
    m = Matrix()
    assert m.snake_pos(9) == (1, 8)
    assert m.snake_pos(17) == (1, 0)

def test_snake_pos_row2_left_to_right():
    m = Matrix()
    assert m.snake_pos(18) == (2, 0)

def test_snake_pos_covers_all_pixels():
    m = Matrix()
    positions = {m.snake_pos(i) for i in range(ROWS * COLS)}
    assert len(positions) == ROWS * COLS
