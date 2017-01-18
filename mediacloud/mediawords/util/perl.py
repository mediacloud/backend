#
# Perl (Inline::Perl) helpers
#
import re
from typing import Union

from mediawords.util.log import create_logger

l = create_logger(__name__)


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


class McConvertDBDPgArgumentsToPsycopg2FormatException(Exception):
    pass


# MC_REWRITE_TO_PYTHON: remove after porting queries to named parameter style
def convert_dbd_pg_arguments_to_psycopg2_format(*query_parameters: Union[list, tuple], skip_decoding=False) -> tuple:
    """Convert DBD::Pg's question mark-style SQL query parameters to psycopg2's syntax."""
    if len(query_parameters) == 0:
        raise McConvertDBDPgArgumentsToPsycopg2FormatException('No query or its parameters.')

    if not skip_decoding:
        # Coming from Perl?
        if isinstance(query_parameters[0], bytes):
            query_parameters = decode_object_from_bytes_if_needed(query_parameters)

    query = query_parameters[0]

    if isinstance(query, bytes):
        raise McConvertDBDPgArgumentsToPsycopg2FormatException(
            'Query "%s" is still "bytes"; did you forget to decode it to "string"?' % str(query)
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
                r'(?P<whitespace_before_question_mark>\s|,|\()\?(?P<whitespace_after_question_mark>\s|,|\)|(::))'
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
                + '(?P<whitespace_after_dollar_sign>\s|,|\)|(::))'
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


def psycopg2_exception_due_to_boolean_passed_as_int_column(exception_message: str,
                                                           statement: str,
                                                           position_in_statement: int) -> Union[str, None]:
    """Given the psycopg2's exception message, tests if the exception is due to booleans being passed as ints, and if
    so, returns the affected column that should be cast to bool."""
    # MC_REWRITE_TO_PYTHON: remove after porting all Perl code to Python

    if exception_message is None:
        return None

    # INSERT / UPDATE
    matches = re.search('column "(.+?)" is of type boolean but expression is of type integer', exception_message)
    if matches is not None:
        affected_column = matches.group(1)
        return affected_column

    # SELECT (supports only basic "WHERE column = 1" statements, but should be enough to make select() work)
    if 'operator does not exist: boolean = integer' in exception_message:
        statement_to_position = statement[:position_in_statement]
        if not statement_to_position.endswith('='):
            l.warn("Unable to parse column out of statement '%s' at position %d" % (statement, position_in_statement))
            return None
        statement_to_position = re.sub('\s*=$', '', statement_to_position)
        matches = re.search('\s(\S+?)$', statement_to_position)
        if matches is None:
            l.warn("Unable to parse column out of statement '%s' at position %d" % (statement, position_in_statement))
            return None
        affected_column = matches.group(1)
        return affected_column

    # Fallback
    return None


class McCastIntToBoolInDictException(Exception):
    pass


def cast_int_to_bool_in_dict(dictionary: dict, key: str) -> dict:
    """Cast Perl's ints to bools to be able to use them with psycopg2."""
    # MC_REWRITE_TO_PYTHON: remove after porting all Perl code to Python
    if key is None:
        raise McCastIntToBoolInDictException('Key is None')

    if key not in dictionary:
        raise McCastIntToBoolInDictException("Key '%s' is not in hash %s" % (key, dictionary))
    if not isinstance(dictionary[key], int):
        raise McCastIntToBoolInDictException("Value for '%s' in hash %s is not int" % (key, dictionary))

    if dictionary[key] == 0:
        dictionary[key] = False
    elif dictionary[key] == 1:
        dictionary[key] = True
    else:
        raise McCastIntToBoolInDictException("Value for '%s' in hash %s is neither 0 not 1" % (key, dictionary))

    return dictionary
