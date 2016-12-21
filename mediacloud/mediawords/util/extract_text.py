from mediawords.util.log import create_logger
from mediawords.util.perl import decode_string_from_bytes_if_needed
import readability.readability

l = create_logger(__name__)


def extractor_name():
    """Return extractor name (typically used for tagging stories with extractor version)."""
    # FIXME read straight from the installed package
    return 'readability-lxml-0.6.2'


def extract_article_from_html(html: str) -> str:
    """Extract article HTML from a full HTML file."""
    # FIXME move HTML stripping here too
    html = decode_string_from_bytes_if_needed(html)
    if html is None or html == '':
        return ''

    try:
        doc = readability.readability.Document(html)

        doc_title = doc.short_title().strip()
        doc_summary = doc.summary().strip()

        extracted_text = "%s\n\n%s" % (doc_title, doc_summary)

    except Exception as ex:
        l.error('Exception raised while extracting HTML: %s' % str(ex))
        extracted_text = ''

    return extracted_text
