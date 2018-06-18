#
# Perl (Inline::Perl) helpers
#
from enum import Enum
import re
from typing import Union

from mediawords.util.log import create_logger

log = create_logger(__name__)


class McDecodeObjectFromBytesIfNeededException(Exception):
    pass


# MC_REWRITE_TO_PYTHON: remove after porting all Perl code to Python
def decode_object_from_bytes_if_needed(obj: Union[dict, list, tuple, str, bytes, None]) \
        -> Union[dict, list, tuple, str, None]:
    """Convert object (dictionary, list or string) from 'bytes' string to 'unicode' if needed."""

    def __decode_string_from_bytes_if_needed(string: Union[int, str, bytes, None]) -> Union[int, str, None]:
        """Convert 'bytes' string to 'unicode' if needed.
        (http://search.cpan.org/dist/Inline-Python/Python.pod#PORTING_YOUR_INLINE_PYTHON_CODE_FROM_2_TO_3)"""
        if string is not None:
            if isinstance(string, bytes):
                # mimic perl decode replace on error behavior
                string = string.decode(encoding='utf-8', errors='replace')
        return string

    if isinstance(obj, dict):
        result = dict()
        for k, v in obj.items():
            k = decode_object_from_bytes_if_needed(k)
            v = decode_object_from_bytes_if_needed(v)
            result[k] = v
    elif isinstance(obj, list):
        result = list()
        for v in obj:
            v = decode_object_from_bytes_if_needed(v)
            result.append(v)
    elif isinstance(obj, tuple):
        result = list()
        for v in obj:
            v = decode_object_from_bytes_if_needed(v)
            result.append(v)
        result = tuple(result)
    elif isinstance(obj, bytes):
        result = __decode_string_from_bytes_if_needed(obj)
    else:
        result = obj
    return result


def decode_str_from_bytes_if_needed(obj: Union[bytes, str, None]) -> Union[str, None]:
    """Call decode_object_from_bytes_if_needed by only accept bytes and strings and only output strings."""
    decode = decode_object_from_bytes_if_needed(obj)
    if type(decode) not in (type('foo'), type(None)):
        raise McDecodeObjectFromBytesIfNeededException("decoded object type '%s' is not str or None" % (type(obj, )))

    return str(decode) if decode is not None else None


class McConvertDBDPgArgumentsToPsycopg2FormatException(Exception):
    pass


# MC_REWRITE_TO_PYTHON: remove after porting queries to named parameter style
def convert_dbd_pg_arguments_to_psycopg2_format(*query_parameters: Union[list, tuple], skip_decoding=False) -> tuple:
    """Convert DBD::Pg's question mark-style SQL query parameters to psycopg2's syntax."""

    def __replace_double_question_marks_or_return_none(q: str, q_args: list) -> Union[tuple, None]:
        """Replace "??" parameters with psycopg2's "%s" and tuple parameter, or return None if not found."""

        double_question_mark_regex = re.compile("""
            (?P<in_statement>\sIN\s)    # "(WHERE) column IN"
            \(\s*\?\?\s*\)              # "(??)" with optional spaces around
        """, flags=re.I | re.X)
        double_question_mark_replacement = r'\g<in_statement>%s'

        double_question_mark_count = len(re.findall(double_question_mark_regex, q))
        if double_question_mark_count > 0:
            if double_question_mark_count > 1:
                raise McConvertDBDPgArgumentsToPsycopg2FormatException("""
                    More than one double question mark found
                    in query "%(query)s" (arguments: %(query_args)s)
                """ % {
                    'query': q,
                    'query_args': q_args,
                })

            q = re.sub(double_question_mark_regex, double_question_mark_replacement, q)

            if not isinstance(q_args, tuple):  # might have been converted previously
                # Convert arguments to first (and only) psycopg2's query parameter
                # (which should be a tuple: http://stackoverflow.com/a/28117658/200603)
                q_args = tuple(q_args)
                q_args = (q_args,)

            return q, q_args

        else:
            return None

    def __replace_question_marks_or_return_none(q: str, q_args: list) -> Union[tuple, None]:
        """Replace "?" parameters with psycopg2's "%s", or return None if not found."""

        question_mark_regex = re.compile("""
            (?P<char_before_question_mark>\s|,|\()      # Question mark preceded by whitespace, comma or bracket
            \?                                          # Question mark
            (?=(\s|,|\)|(::)|$))                        # Lookahead and make sure question mark is singled out
        """, flags=re.I | re.X)
        question_mark_replacement = r'\g<char_before_question_mark>%s'

        question_mark_count = len(re.findall(question_mark_regex, q))
        if question_mark_count > 0:

            q = re.sub(question_mark_regex, question_mark_replacement, q)

            # Convert arguments to psycopg2's argument tuple
            if not isinstance(q_args, tuple):  # might have been converted previously
                q_args = tuple(q_args)

            return q, q_args

        else:
            return None

    def __replace_dollar_signs_or_return_none(q: str, q_args: list) -> Union[tuple, None]:
        """Replace "$1" parameters with psycopg2's "%(param_1)s", or return None if not found."""

        dollar_sign_regex = re.compile("""
            (?P<char_before_dollar_sign>\s|,|\()    # Dollar sign preceded by whitespace, comma or bracket
            \$(?P<param_index>\d)                   # Dollar sign with a single-digit index ("$1", "$2", ...)
            (?=(\s|,|\)|(::)|$))                    # Lookahead and make sure dollar sign is singled out
        """, flags=re.I | re.X)
        dollar_sign_replacement = r'\g<char_before_dollar_sign>%(param_\g<param_index>)s'

        dollar_sign_unique_indexes = set([x[1] for x in re.findall(dollar_sign_regex, q)])
        dollar_sign_unique_count = len(dollar_sign_unique_indexes)
        if dollar_sign_unique_count > 0:

            q = re.sub(dollar_sign_regex, dollar_sign_replacement, q)

            # Convert arguments to psycopg2's argument dictionary
            if not isinstance(q_args, dict):  # might have been converted previously
                q_args_dict = {}
                for i in range(0, len(q_args)):
                    q_args_dict['param_%d' % (i + 1)] = q_args[i]
                q_args = q_args_dict

            return q, q_args

        else:
            return None

    # ---

    if len(query_parameters) == 0:
        raise McConvertDBDPgArgumentsToPsycopg2FormatException('No query or its parameters.')

    query = query_parameters[0]
    query_args = list(query_parameters[1:])

    if len(query) == 0:
        raise McConvertDBDPgArgumentsToPsycopg2FormatException('Query is empty or undefined.')

    query = decode_object_from_bytes_if_needed(query)

    # If psycopg2's tuple of dictionary parameters were passed, there's nothing for us to do
    if len(query_args) == 1 and (isinstance(query_args[0], tuple) or isinstance(query_args[0], dict)):
        return query_parameters

    #
    # At this point, it should be a DBD::Pg's question mark-style query.
    #

    if not skip_decoding:
        query_args = decode_object_from_bytes_if_needed(query_args)

    log.debug("Query to convert: %s; with arguments: %s" % (query, query_args))

    # If there are no query parameters, there's nothing more to do
    if len(query_args) == 0:
        query_args = None

    else:

        # Matches 'PostgreSQL''s quoted literals'
        quoted_literal_regex = r"('(?:[^']+|'')+')"

        # Split SQL query into literals and not literals, iterate over all of them, replace parameters to psycopg2-style
        # only for the non-literals parts
        split_query = re.split(quoted_literal_regex, query)
        converted_query = ""

        class PlaceholderType(Enum):
            double_question_mark = 1
            question_mark = 2
            dollar_signs = 3

        placeholder_type = None

        for query_part in split_query:
            if re.match("^" + quoted_literal_regex + "$", query_part):
                # Don't touch quoted literals
                pass
            else:

                double_question_mark = __replace_double_question_marks_or_return_none(q=query_part, q_args=query_args)
                if double_question_mark is not None:

                    if placeholder_type is not None:
                        if placeholder_type != PlaceholderType.double_question_mark:
                            raise McConvertDBDPgArgumentsToPsycopg2FormatException("""
                                Mixed placeholder types? Query: %(query)s, arguments: %(query_args)s
                            """ % {'query': query, 'query_args': query_args})
                    placeholder_type = PlaceholderType.double_question_mark

                    query_part = double_question_mark[0]
                    query_args = double_question_mark[1]

                else:

                    question_mark = __replace_question_marks_or_return_none(q=query_part, q_args=query_args)
                    if question_mark is not None:

                        if placeholder_type is not None:
                            if placeholder_type != PlaceholderType.question_mark:
                                raise McConvertDBDPgArgumentsToPsycopg2FormatException("""
                                    Mixed placeholder types? Query: %(query)s, arguments: %(query_args)s
                                """ % {'query': query, 'query_args': query_args})
                        placeholder_type = PlaceholderType.question_mark

                        query_part = question_mark[0]
                        query_args = question_mark[1]

                    else:

                        dollar_signs = __replace_dollar_signs_or_return_none(q=query_part, q_args=query_args)
                        if dollar_signs is not None:

                            if placeholder_type is not None:
                                if placeholder_type != PlaceholderType.dollar_signs:
                                    raise McConvertDBDPgArgumentsToPsycopg2FormatException("""
                                        Mixed placeholder types? Query: %(query)s, arguments: %(query_args)s
                                    """ % {'query': query, 'query_args': query_args})
                            placeholder_type = PlaceholderType.dollar_signs

                            query_part = dollar_signs[0]
                            query_args = dollar_signs[1]

            converted_query += query_part

        if placeholder_type is None:
            raise McConvertDBDPgArgumentsToPsycopg2FormatException("""
                Query has arguments coming from Perl, but none of the supported placeholders ("?", "??", "$1")
                were found. Query: %(query)s; arguments: %(query_args)s
            """ % {'query': query, 'query_args': query_args})

        query = converted_query

    if query_args is None:
        query_parameters = (query,)
    else:
        query_parameters = (query, query_args,)

    log.debug("Converted to: %s" % str(query_parameters))

    return query_parameters
