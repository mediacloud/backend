import random
from colorsys import hsv_to_rgb, rgb_to_hsv
from typing import List

from mediawords.db import DatabaseHandler
from mediawords.util.perl import decode_object_from_bytes_if_needed

__MC_COLORS = [
    '1f77b4', 'aec7e8', 'ff7f0e', 'ffbb78', '2ca02c',
    '98df8a', 'd62728', 'ff9896', '9467bd', 'c5b0d5',
    '8c564b', 'c49c94', 'e377c2', 'f7b6d2', '7f7f7f',
    'c7c7c7', 'bcbd22', 'dbdb8d', '17becf', '9edae5',
    '84c4ce', 'ffa779', 'cc5ace', '6f11c9', '6f3e5d',
]


def hex_to_rgb(hex_color: str) -> tuple:
    """Get R, G, B channels from hex color, e.g. "FF0000"."""
    if hex_color.startswith('#'):
        hex_color = hex_color[1:]
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))


def rgb_to_hex(r: int, g: int, b: int) -> str:
    """Get hex color (e.g. "FF0000") from R, G, B channels."""
    return '%02x%02x%02x' % (int(r), int(g), int(b),)


def analogous_color(color: str, return_slices: int = 4, split_slices: int = 12) -> List[str]:
    """Generate analogous color scheme starting with the provided color.

    Analogous color scheme is the one in which the colors lie next to each other on the color wheel.

    By default this method splits up the color wheel into 12 pieces and returns the original parameter color plus the
    next 3 pieces of the wheel (4 colors in total). For example, by padding '0000ff' (blue) you would get back '0000ff'
    (blue -- the original color) '80000ff' (purple), 'ff00ff' (pink) and 'ff0080' (hot pink) colors.

    Ported from https://metacpan.org/pod/Color::Mix#analogous().

    :param color: Starting color
    :param return_slices: Number of color slices to return
    :param split_slices: Number of slices to split the color wheel into
    :return: Generated colors starting with the parameter color
    """
    color = decode_object_from_bytes_if_needed(color)

    def shift_hue(hue: int, angle_: float) -> int:
        return int((hue + angle_) % 360)

    def rotate_color(color_: str, angle_: float) -> str:
        r, g, b = hex_to_rgb(color_)
        h, s, v = rgb_to_hsv(r, g, b)
        h *= 360
        h = shift_hue(hue=h, angle_=angle_)
        h /= 360
        r, g, b = hsv_to_rgb(h, s, v)
        r = int(r)
        g = int(g)
        b = int(b)
        return rgb_to_hex(r, g, b)

    angle = 360 / split_slices

    colors = [color]
    for x in range(1, return_slices):
        new_color = rotate_color(color_=color, angle_=angle * x)
        colors.append(new_color)

    return colors


def get_consistent_color(db: DatabaseHandler, item_set: str, item_id: str) -> str:
    """Return the same hex color (e.g. "ff0000" for the same set / ID combination every time this function is called."""
    item_set = decode_object_from_bytes_if_needed(item_set)
    item_id = decode_object_from_bytes_if_needed(item_id)

    # Always return grey for null or not typed values
    if item_id.lower() in {'null', 'not typed'}:
        return '999999'

    color = db.query("""SELECT color FROM color_sets WHERE color_set = %(item_set)s AND id = %(item_id)s""", {
        'item_set': item_set,
        'item_id': item_id,
    }).flat()
    if color is not None and len(color):
        if isinstance(color, list):
            color = color[0]
        return color

    set_colors = db.query("""SELECT color FROM color_sets WHERE color_set = %(item_set)s""", {
        'item_set': item_set,
    }).flat()
    if set_colors is not None:
        if not isinstance(set_colors, list):
            set_colors = [set_colors]

    existing_colors = set()

    if set_colors is not None:
        for color in set_colors:
            existing_colors.add(color)

    # Use the hard coded palette of 25 colors if possible
    new_color = None
    for color in __MC_COLORS:
        if color not in existing_colors:
            new_color = color
            break

    # Otherwise, just generate a random color
    if new_color is None:
        colors = analogous_color(color='0000ff', return_slices=256, split_slices=255)
        new_color = random.choice(colors)

    db.create(table='color_sets', insert_hash={
        'color_set': item_set,
        'id': item_id,
        'color': new_color,
    })

    return new_color
