from mediawords.util.colors import analogous_color


def test_analogous_color():
    starting_color = '0000ff'

    colors = analogous_color(color=starting_color, return_slices=1, split_slices=255)
    assert len(colors) == 1
    assert colors[0].lower() == starting_color

    colors = analogous_color(color=starting_color, return_slices=256, split_slices=255)
    assert len(colors) == 256
    assert colors[0].lower() == starting_color
    assert colors[1].lower() == '0400ff'
    assert colors[-2].lower() == '0008ff'
    assert colors[-1].lower() == starting_color
