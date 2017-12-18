#
# Uses "hausastemmer" Python module:
#
# * https://github.com/berkmancenter/mediacloud-hausastemmer
# * https://pypi.python.org/pypi/hausastemmer/1.0
#
import hausastemmer
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.log import create_logger

log = create_logger(__name__)


def py_hausa_stem(token):
    """Used by Perl code to do Hausa stemming."""
    # MC_REWRITE_TO_PYTHON: simplify after rewriting language module to Python.
    token = decode_object_from_bytes_if_needed(token)
    return hausastemmer.stem(token)
