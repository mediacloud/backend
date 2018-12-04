from mediawords.db import DatabaseHandler
from mediawords.util.perl import decode_object_from_bytes_if_needed


def create(db: DatabaseHandler, download: dict, extract: dict) -> dict:
    """Create a download_text hash and insert it into the database. Delete any existing download_text row for the
    download."""

    # FIXME don't pass freeform "extract" dict, we need just the "extracted_text"

    download = decode_object_from_bytes_if_needed(download)
    extract = decode_object_from_bytes_if_needed(extract)

    db.query("""
        DELETE FROM download_texts
        WHERE downloads_id = %(downloads_id)s
    """, {'downloads_id': download['downloads_id']})

    download_text = db.query("""
        INSERT INTO download_texts (downloads_id, download_text, download_text_length)
        VALUES (%(downloads_id)s, %(download_text)s, CHAR_LENGTH(%(download_text)s))
        RETURNING *
    """, {
        'downloads_id': download['downloads_id'],
        'download_text': extract['extracted_text'],
    }).hash()

    db.query("""
        UPDATE downloads
        SET extracted = 't'
        WHERE downloads_id = %(downloads_id)s
    """, {'downloads_id': download['downloads_id']})

    return download_text
