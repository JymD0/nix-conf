from ledmatrix import ROWS, COLS, Matrix
from ledmatrix.fire import _step_heat, _build_fire_frame


def _empty_heat():
    return [[0.0] * COLS for _ in range(ROWS)]


def test_step_heat_seeds_bottom_rows():
    heat = _step_heat(_empty_heat())
    assert heat[ROWS - 1][0] >= 180
    assert heat[ROWS - 2][0] >= 160


def test_step_heat_returns_correct_shape():
    heat = _step_heat(_empty_heat())
    assert len(heat) == ROWS
    assert all(len(row) == COLS for row in heat)


def test_step_heat_values_in_range():
    heat = _empty_heat()
    for _ in range(10):
        heat = _step_heat(heat)
    for row in heat:
        for v in row:
            assert 0 <= v <= 255


def test_build_fire_frame_returns_matrix():
    heat = _step_heat(_empty_heat())
    m = _build_fire_frame(heat)
    assert isinstance(m, Matrix)


def test_build_fire_frame_brightness_in_range():
    heat = _step_heat(_empty_heat())
    m = _build_fire_frame(heat)
    for r in range(ROWS):
        for c in range(COLS):
            assert 0 <= m.get(r, c) <= 255
