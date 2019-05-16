from webapp.util.colors import hex_to_rgb


def test_hex_to_rgb():
    assert hex_to_rgb('ff0000') == (255, 0, 0,)
    assert hex_to_rgb('FFFFFF') == (255, 255, 255,)
    assert hex_to_rgb('#ff0000') == (255, 0, 0,)
    assert hex_to_rgb('#FFFFFF') == (255, 255, 255,)
