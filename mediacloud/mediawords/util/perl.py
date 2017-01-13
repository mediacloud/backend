#
# Perl (Inline::Perl) helpers
#
import re
from typing import Union

from mediawords.util.log import create_logger

l = create_logger(__name__)


# FIXME MC_REWRITE_TO_PYTHON: remove after porting all Perl code to Python
def decode_string_from_bytes_if_needed(string: Union[int, str, bytes, None]) -> Union[int, str, None]:
    """Convert 'bytes' string to 'unicode' if needed.
    (http://search.cpan.org/dist/Inline-Python/Python.pod#PORTING_YOUR_INLINE_PYTHON_CODE_FROM_2_TO_3)"""
    if string is not None:
        if isinstance(string, bytes):
            # mimic perl decode replace on error behavior
            string = string.decode(encoding='utf-8', errors='replace')
    return string


# FIXME MC_REWRITE_TO_PYTHON: remove after porting all Perl code to Python
def decode_object_from_bytes_if_needed(obj: Union[dict, list, str, bytes, None]) -> Union[dict, list, str, None]:
    """Convert object (dictionary, list or string) from 'bytes' string to 'unicode' if needed."""
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
    else:
        result = decode_string_from_bytes_if_needed(obj)
    return result


class McConvertDBDPgArgumentsToPsycopg2FormatException(Exception):
    pass


# FIXME MC_REWRITE_TO_PYTHON: remove after porting queries to named parameter style
def convert_dbd_pg_arguments_to_psycopg2_format(*query_parameters: Union[list, tuple]) -> tuple:
    """Convert DBD::Pg's question mark-style SQL query parameters to psycopg2's syntax."""
    if len(query_parameters) == 0:
        raise McConvertDBDPgArgumentsToPsycopg2FormatException('No query or its parameters.')

    query = query_parameters[0]
    if isinstance(query, bytes):
        raise McConvertDBDPgArgumentsToPsycopg2FormatException(
            'Query is still "bytes"; did you forget to decode it to "string"?'
        )
    if len(query) == 0:
        raise McConvertDBDPgArgumentsToPsycopg2FormatException('Query is empty or undefined.')
    query = str(query)

    query_args = query_parameters[1:]

    l.debug("Query to convert: %s; with arguments: %s" % (query, query_args))

    # If psycopg2's tuple of dictionary parameters were passed, there's nothing for us to do
    if len(query_args) == 1 and (isinstance(query_args[0], tuple) or isinstance(query_args[0], dict)):
        return query_parameters

    #
    # At this point, it should be a DBD::Pg's question mark-style query.
    #

    # "When parameters are used, in order to include a literal % in the query you can use the %% string."
    #
    # FIXME MC_REWRITE_TO_PYTHON: both psycopg2 and DBD::Pg queries get their %'s doubled here; this is usually not a
    # big deal ("LIKE 'Abc%'" and "LIKE 'Abc%%'" work the same), but after converting queries to psycopg2's syntax, the
    # following statement should be removed.
    query = query.replace('%', '%%')

    # If there are no query parameters, there's nothing more to do
    if len(query_args) == 0:
        query_args = None

    else:

        # Replace "??" parameters with psycopg2's "%s" and tuple parameter
        double_question_mark_regex = re.compile(r'(?P<in_statement>\sIN\s)\(\s*\?\?\s*\)', flags=re.I)
        double_question_mark_count = len(re.findall(double_question_mark_regex, query))
        if double_question_mark_count > 0:
            if double_question_mark_count > 1:
                raise McConvertDBDPgArgumentsToPsycopg2FormatException("""
                    More than one double question mark found
                    in query "%(query)s" (arguments: %(query_args)s)
                """ % {
                    'query': query,
                    'query_args': query_args,
                })

            query = re.sub(double_question_mark_regex, r'\g<in_statement>%s', query)

            # Convert arguments to first (and only) psycopg2's query parameter
            # (which should be a tuple: http://stackoverflow.com/a/28117658/200603)
            query_args = tuple(query_args)
            query_args = (query_args,)

        else:

            # Make regexes match at the end-of-line too
            query = " %s " % query

            # Replace "?" parameters with psycopg2's "%s"
            question_mark_regex = re.compile(
                r'(?P<whitespace_before_question_mark>\s|,|\()\?(?P<whitespace_after_question_mark>\s|,|\))'
            )
            question_mark_count = len(re.findall(question_mark_regex, query))
            if question_mark_count > 0:
                if question_mark_count != len(query_args):
                    raise McConvertDBDPgArgumentsToPsycopg2FormatException("""
                        Question mark count (%(question_mark_count)d)
                        does not match the argument count (%(argument_count)d
                        in query "%(query)s" (arguments: %(query_args)s)
                    """ % {
                        'question_mark_count': question_mark_count,
                        'argument_count': len(query_args),
                        'query': query,
                        'query_args': query_args,
                    })

                query = re.sub(
                    question_mark_regex,
                    r'\g<whitespace_before_question_mark>%s\g<whitespace_after_question_mark>',
                    query
                )

                # Convert arguments to psycopg2's argument tuple
                query_args = tuple(query_args)

            # Replace "$1" parameters with psycopg2's "%(param_1)s"
            dollar_sign_regex = re.compile(
                r'(?P<whitespace_before_dollar_sign>\s|,|\()'
                + '\$(?P<param_index>\d)'
                + '(?P<whitespace_after_dollar_sign>\s|,|\))'
            )
            dollar_sign_unique_indexes = set([x[1] for x in re.findall(dollar_sign_regex, query)])
            dollar_sign_unique_count = len(dollar_sign_unique_indexes)
            if dollar_sign_unique_count > 0:
                if dollar_sign_unique_count != len(query_args):
                    raise McConvertDBDPgArgumentsToPsycopg2FormatException("""
                        Unique dollar sign count (%(dollar_sign_unique_count)d)
                        does not match the argument count (%(argument_count)d
                        in query "%(query)s" (arguments: %(query_args)s)
                    """ % {
                        'dollar_sign_unique_count': dollar_sign_unique_count,
                        'argument_count': len(query_args),
                        'query': query,
                        'query_args': query_args,
                    })

                query = re.sub(
                    dollar_sign_regex,
                    r'\g<whitespace_before_dollar_sign>%(param_\g<param_index>)s\g<whitespace_after_dollar_sign>',
                    query
                )

                # Convert arguments to psycopg2's argument dictionary
                query_args_dict = {}
                for i in range(0, dollar_sign_unique_count):
                    query_args_dict['param_%d' % (i + 1)] = query_args[i]
                query_args = query_args_dict

            # Remove extra whitespace that was just added
            query = query.strip()

    if query_args is None:
        query_parameters = (query,)
    else:
        query_parameters = (query, query_args,)

    l.debug("Converted to: %s" % str(query_parameters))

    return query_parameters
