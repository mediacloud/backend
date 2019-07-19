#!/usr/bin/env python3

from mediawords.db import connect_to_db, DatabaseHandler
from mediawords.job.sitemap.fetch_media_pages import FetchMediaPages
from mediawords.util.log import create_logger

log = create_logger(__name__)


def add_all_media_to_sitemap_queue(db: DatabaseHandler):
    """Add all media IDs to XML sitemap fetching queue."""
    log.info("Fetching all media IDs...")
    media_ids = db.query("""
        SELECT media_id
        FROM media
        ORDER BY media_id
    """).flat()
    for media_id in media_ids:
        log.info("Adding media ID %d" % media_id)
        FetchMediaPages.add_to_queue(media_id=media_id)


def add_us_media_to_sitemap_queue():
    us_media_ids = [
        104828, 1089, 1092, 1095, 1098, 1101, 1104, 1110, 1145, 1149, 1150, 14, 15, 1747, 1750, 1751, 1752, 1755, 18268,
        18710, 18775, 18839, 18840, 19334, 19643, 1, 22088, 25349, 25499, 27502, 2, 40944, 4415, 4419, 4442, 4, 6218,
        623382, 64866, 65, 6, 751082, 7, 8,
    ]
    us_media_ids = sorted(us_media_ids)
    for media_id in us_media_ids:
        log.info("Adding media ID %d" % media_id)
        FetchMediaPages.add_to_queue(media_id=media_id)


def add_colombia_media_to_sitemap_queue():
    colombia_media_ids = [
        38871, 40941, 42072, 57482, 58360, 58430, 58660, 59058, 59589, 60338, 61607, 62209, 63889, 63921, 74622, 120254,
        127258, 211343, 277109, 280236, 281924, 282160, 282256, 282463, 282769, 283998, 297900, 324728, 325564, 325966,
        326385, 326782, 328053, 329452, 329735, 330235, 330576, 331318, 331987, 336326, 336339, 336682, 336993, 340969,
        341040, 347037, 347551, 348018, 348021, 348023, 348024, 348026, 348029, 348031, 348032, 348033, 348034, 348035,
        348037, 348038, 348040, 348041, 348043, 348044, 348048, 348049, 348050, 348052, 348054, 348058, 348060, 348061,
        348062, 348063, 348064, 348066, 348067, 348068, 348069, 348070, 348072, 348073, 348074, 348075, 348077, 348078,
        348079, 348081, 348083, 348084, 357882, 359251, 362163, 362287, 362386, 362587, 363868, 467798, 540413, 552466,
        552579, 558121, 559945, 563374, 565190, 565808, 567421, 651490, 651491, 651492, 651493, 651494, 655394, 655395,
        683226, 683288, 683554, 695708, 695709, 695710, 695711, 695712, 695713, 695715, 845114, 849762, 879769, 1180124,
        1195863, 1195913, 1207868, 1208757, 1265854,
    ]
    colombia_media_ids = sorted(colombia_media_ids)
    for media_id in colombia_media_ids:
        log.info("Adding media ID %d" % media_id)
        FetchMediaPages.add_to_queue(media_id=media_id)


if __name__ == "__main__":
    db_ = connect_to_db()
    # add_all_media_to_sitemap_queue(db=db_)
    # add_us_media_to_sitemap_queue()
    add_colombia_media_to_sitemap_queue()
