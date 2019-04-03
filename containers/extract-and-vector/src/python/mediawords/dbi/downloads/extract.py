"""Functions for extracting downloads."""

import re
from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.dbi.download_texts import create
from mediawords.dbi.downloads.store import fetch_content
from mediawords.dbi.stories.extractor_arguments import PyExtractorArguments
from mediawords.dbi.stories.extractor_version import update_extractor_version_tag
from mediawords.dbi.stories.process import process_extracted_story
from mediawords.util.extract_article_from_page import extract_article_html_from_page_html
from mediawords.util.parse_html import html_strip
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

# Mininmum content length to extract (assuming that it has some HTML in it)
MIN_CONTENT_LENGTH_TO_EXTRACT = 4096

# If the extracted text length is less than this, try finding content in javascript variable
MIN_EXTRACTED_LENGTH_FOR_JS_EXTRACTION = 256

# these are initialized by calling the various get_*_story() functions below
_inline_store = None
_amazon_s3_store = None
_postgresql_store = None
_store_for_writing = None


def _get_extractor_results_cache(db: DatabaseHandler, download: dict) -> Optional[dict]:
    """Get extractor results from cache.

    Return:
    None if there is a miss or a dict in the form of extract_content() if there is a hit.
    """
    download = decode_object_from_bytes_if_needed(download)

    r = db.query("""
        SELECT extracted_html, extracted_text
        FROM cache.extractor_results_cache
        WHERE downloads_id = %(a)s
    """, {'a': download['downloads_id']}).hash()

    log.debug("EXTRACTOR CACHE HIT" if r is not None else "EXTRACTOR CACHE MISS")

    return r


def _set_extractor_results_cache(db, download: dict, results: dict) -> None:
    """Store results in extractor cache and manage size of cache."""

    # This cache is used as a backhanded way of extracting stories asynchronously in the topic spider.  Instead of
    # submitting extractor jobs and then directly checking whether a given story has been extracted, we just
    # throw extraction jobs in chunks into the extractor job and cache the results.  Then if we re-extract
    # the same story shortly after, this cache will hit and the cost will be trivial.

    download = decode_object_from_bytes_if_needed(download)
    results = decode_object_from_bytes_if_needed(results)

    # Upsert cache entry
    db.query("""
        INSERT INTO cache.extractor_results_cache (
            extracted_html,
            extracted_text,
            downloads_id
        ) VALUES (
            %(extracted_html)s,
            %(extracted_text)s,
            %(downloads_id)s
        ) ON CONFLICT (downloads_id) DO UPDATE SET
            extracted_html = EXCLUDED.extracted_html,
            extracted_text = EXCLUDED.extracted_text
    """, {
        'extracted_html': results['extracted_html'],
        'extracted_text': results['extracted_text'],
        'downloads_id': int(download['downloads_id']),
    })


def extract(db: DatabaseHandler, download: dict, extractor_args: PyExtractorArguments = PyExtractorArguments()) -> dict:
    """Extract the content for the given download.

    Arguments:
    db - db handle
    download - download dict from db
    use_cache - get and set results in extractor cache

    Returns:
    see extract_content() below

    """
    download = decode_object_from_bytes_if_needed(download)

    downloads_id = download['downloads_id']

    if extractor_args.use_cache():
        log.debug("Fetching cached extractor results for download {}...".format(downloads_id))
        results = _get_extractor_results_cache(db, download)
        if results is not None:
            return results

    log.debug("Fetching content for download {}...".format(downloads_id))
    content = fetch_content(db, download)

    log.debug("Extracting {} characters of content for download {}...".format(len(content), downloads_id))
    results = extract_content(content)
    log.debug(
        "Done extracting {} characters of content for download {}.".format(len(content), downloads_id))

    if extractor_args.use_cache():
        log.debug("Caching extractor results for download {}...".format(downloads_id))
        _set_extractor_results_cache(db, download, results)

    return results


def _call_extractor_on_html(content: str) -> dict:
    """Call extractor on the content."""
    content = decode_object_from_bytes_if_needed(content)

    extractor_results = extract_article_html_from_page_html(content)

    extracted_html = extractor_results['extracted_html']
    extractor_version = extractor_results['extractor_version']
    extracted_text = html_strip(extracted_html)

    return {
        'extracted_html': extracted_html,
        'extracted_text': extracted_text,
        'extractor_version': extractor_version,
    }


def extract_content(content: str) -> dict:
    """Extract text and html from the provided HTML content.

    Extraction means pulling the substantive text out of a web page, eliminating the navigation, ads, and other
    boilerplate content.

    Arguments:
    content - html from which to extract

    Returns:
    a dict in the form {'extracted_html': html, 'extracted_text': text}

    """
    content = decode_object_from_bytes_if_needed(content)

    # Don't run through expensive extractor if the content is short and has no html
    if len(content) < MIN_CONTENT_LENGTH_TO_EXTRACT and re.search(r'<.*>', content) is None:
        log.info("Content length is less than MIN_CONTENT_LENGTH_TO_EXTRACT and has no HTML so skipping extraction")
        ret = {'extracted_html': content, 'extracted_text': content}
    else:
        ret = _call_extractor_on_html(content)

    return ret


def extract_and_create_download_text(db: DatabaseHandler, download: dict, extractor_args: PyExtractorArguments) -> dict:
    """Extract the download and create a download_text from the extracted download."""
    download = decode_object_from_bytes_if_needed(download)

    downloads_id = download['downloads_id']

    log.debug("Extracting download {}...".format(downloads_id))
    extraction_result = extract(db=db, download=download, extractor_args=extractor_args)
    log.debug("Done extracting download {}.".format(downloads_id))

    download_text = None
    if extractor_args.use_existing():
        log.debug("Fetching download text for download {}...".format(downloads_id))
        download_text = db.query("""
            SELECT *
            FROM download_texts
            WHERE downloads_id = %(downloads_id)s
        """, {'downloads_id': downloads_id}).hash()

    if download_text is None:
        log.debug("Creating download text for download {}...".format(downloads_id))
        download_text = create(db=db, download=download, extract=extraction_result)

    assert 'stories_id' in download, "It is expected to have 'stories_id' set for a download at this point."

    if not extractor_args.no_tag_extractor_version():
        log.debug("Updating extractor version tag for story {}...".format(download['stories_id']))
        update_extractor_version_tag(
            db=db,
            stories_id=download['stories_id'],
            extractor_version=extraction_result['extractor_version'],
        )

    return download_text


def process_download_for_extractor(db: DatabaseHandler,
                                   download: dict,
                                   extractor_args: PyExtractorArguments = PyExtractorArguments()) -> None:
    """Extract the download and create the resulting download_text entry. If there are no remaining downloads to be
    extracted for the story, call process_extracted_story() on the parent story."""

    download = decode_object_from_bytes_if_needed(download)

    stories_id = download['stories_id']

    log.debug("extract: {} {} {}".format(download['downloads_id'], stories_id, download['url']))

    extract_and_create_download_text(db=db, download=download, extractor_args=extractor_args)

    has_remaining_download = db.query("""
        SELECT downloads_id
        FROM downloads
        WHERE stories_id = %(stories_id)s
          AND extracted = 'f'
          AND type = 'content'
    """, {'stories_id': stories_id}).hash()

    # MC_REWRITE_TO_PYTHON: Perlism
    if has_remaining_download is None:
        has_remaining_download = {}

    if len(has_remaining_download) > 0:
        log.info("Pending more downloads...")

    else:
        story = db.find_by_id(table='stories', object_id=stories_id)
        process_extracted_story(db=db, story=story, extractor_args=extractor_args)
