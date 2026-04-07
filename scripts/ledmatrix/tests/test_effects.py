from ledmatrix import ROWS, COLS, Matrix
from ledmatrix.fire import _step_heat, _build_fire_frame
from ledmatrix.plasma import _build_plasma_frame
from ledmatrix.rain import _make_column, _build_rain_frame, _step_columns
from ledmatrix.metaballs import _make_blob, _build_metaballs_frame, _step_blobs
from ledmatrix.starfield import _make_star, _build_starfield_frame, _step_stars, MAX_Z


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


def test_build_plasma_frame_returns_matrix():
    assert isinstance(_build_plasma_frame(0.0), Matrix)


def test_build_plasma_frame_brightness_in_range():
    m = _build_plasma_frame(1.23)
    for r in range(ROWS):
        for c in range(COLS):
            assert 0 <= m.get(r, c) <= 255


def test_build_plasma_frame_changes_with_t():
    m1 = _build_plasma_frame(0.0)
    m2 = _build_plasma_frame(1.0)
    values1 = [m1.get(r, c) for r in range(ROWS) for c in range(COLS)]
    values2 = [m2.get(r, c) for r in range(ROWS) for c in range(COLS)]
    assert values1 != values2


def test_make_column_has_required_keys():
    col = _make_column()
    assert "pos" in col
    assert "speed" in col
    assert "trail" in col


def test_build_rain_frame_returns_matrix():
    columns = [_make_column() for _ in range(COLS)]
    assert isinstance(_build_rain_frame(columns), Matrix)


def test_build_rain_frame_brightness_in_range():
    columns = [_make_column() for _ in range(COLS)]
    for col in columns:
        col["pos"] = 10.0
    m = _build_rain_frame(columns)
    for r in range(ROWS):
        for c in range(COLS):
            assert 0 <= m.get(r, c) <= 255


def test_step_columns_advances_position():
    columns = [_make_column() for _ in range(COLS)]
    before = [col["pos"] for col in columns]
    _step_columns(columns)
    after = [col["pos"] for col in columns]
    assert all(a >= b for a, b in zip(after, before))


def test_make_blob_has_required_keys():
    blob = _make_blob()
    for key in ("r", "c", "vr", "vc", "radius"):
        assert key in blob


def test_build_metaballs_frame_returns_matrix():
    blobs = [_make_blob() for _ in range(3)]
    assert isinstance(_build_metaballs_frame(blobs), Matrix)


def test_build_metaballs_frame_brightness_in_range():
    blobs = [_make_blob() for _ in range(3)]
    m = _build_metaballs_frame(blobs)
    for r in range(ROWS):
        for c in range(COLS):
            assert 0 <= m.get(r, c) <= 255


def test_step_blobs_moves_positions():
    blobs = [_make_blob() for _ in range(3)]
    before = [(b["r"], b["c"]) for b in blobs]
    _step_blobs(blobs)
    after = [(b["r"], b["c"]) for b in blobs]
    assert before != after


def test_step_blobs_stays_in_bounds():
    blobs = [_make_blob() for _ in range(3)]
    for _ in range(200):
        _step_blobs(blobs)
    for blob in blobs:
        assert 0 <= blob["r"] < ROWS
        assert 0 <= blob["c"] < COLS


def test_make_star_has_required_keys():
    star = _make_star()
    for key in ("x", "y", "z", "speed"):
        assert key in star


def test_make_star_z_in_range():
    for _ in range(20):
        star = _make_star()
        assert 0 < star["z"] <= MAX_Z


def test_build_starfield_frame_returns_matrix():
    stars = [_make_star() for _ in range(30)]
    assert isinstance(_build_starfield_frame(stars), Matrix)


def test_build_starfield_frame_brightness_in_range():
    stars = [_make_star() for _ in range(30)]
    m = _build_starfield_frame(stars)
    for r in range(ROWS):
        for c in range(COLS):
            assert 0 <= m.get(r, c) <= 255


def test_step_stars_decrements_z():
    stars = [_make_star() for _ in range(30)]
    before = [s["z"] for s in stars]
    _step_stars(stars)
    after = [s["z"] for s in stars]
    assert any(a < b or a == MAX_Z for a, b in zip(after, before))
