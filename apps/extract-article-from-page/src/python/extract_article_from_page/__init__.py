from io import StringIO
import re
import sys

# noinspection PyProtectedMember
from pip._internal import main as pip_main

# noinspection PyPackageRequirements
import readability.readability

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

# Cached module versions
__module_version_cache = {}


class McGetPipModuleVersionException(Exception):
    pass


def __get_pip_module_version(module_name):
    """Return module version using Pip (not all modules have "__version__" attribute)."""
    global __module_version_cache

    if module_name not in __module_version_cache:

        f = StringIO()
        sys.stdout = f
        pip_main(['show', module_name])
        sys.stdout = sys.__stdout__

        module_version = None
        for line in f.getvalue().splitlines():
            if line.startswith('Version'):
                module_version = line.split(':', 1)[1].strip()
                break

        if module_version is None:
            raise McGetPipModuleVersionException("Unable to determine '%s' module version" % module_name)

        __module_version_cache[module_name] = module_version

    return __module_version_cache[module_name]


def replace_control_nonprintable_characters(string: str, replacement: str = ' ') -> str:
    """Remove ASCII control characters except for \n, \r, and \t."""

    # Allow 0x09 CHARACTER TABULATION
    # Allow 0x0a LINE FEED (LF)
    # Allow 0x0d CARRIAGE RETURN (CR)
    string = re.sub(r'[\x00-\x08\x0b-\x0c\x0e-\x1f\x7f-\x9f]', replacement, string)

    return string


def extractor_name():
    """Return extractor name (typically used for tagging stories with extractor version)."""
    readability_module = 'readability-lxml'
    readability_version = __get_pip_module_version(readability_module)

    return '%s-%s' % (readability_module, readability_version)


def extract_article_from_page(html: str) -> str:
    """Extract article HTML from a full HTML file."""
    # FIXME move HTML stripping here too
    html = decode_object_from_bytes_if_needed(html)
    if html is None or html == '':
        return ''

    # Control characters will choke Readability
    html = replace_control_nonprintable_characters(html)

    # If any character (e.g. a space, or a NUL byte) repeats itself over and over again, it's not natural language and
    # we don't need it; also, it will make Readability really slow
    html = re.sub(r'(.)\1{256,}', '\1', html)

    # Same with any kind of whitespace; the whitespace character might wary (e.g. "\r\n \r\n ..."), so this is a
    # separate regex
    html = re.sub(r'\s{256,}', '\1', html)

    try:
        doc = readability.readability.Document(html)

        doc_title = doc.short_title().strip()
        doc_summary = doc.summary().strip()

        extracted_text = "{}\n\n{}".format(doc_title, doc_summary)

    except Exception as ex:
        log.error('Exception raised while extracting HTML: %s' % str(ex))
        extracted_text = ''

    return extracted_text
