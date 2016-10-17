#
# Perl (Inline::Perl) helpers
#


# FIXME MC_REWRITE_TO_PYTHON: remove after porting all Perl code to Python
def decode_string_from_bytes_if_needed(string):
    """Convert 'bytes' string to 'unicode' if needed.
    (http://search.cpan.org/dist/Inline-Python/Python.pod#PORTING_YOUR_INLINE_PYTHON_CODE_FROM_2_TO_3)"""
    if string is not None:
        if isinstance(string, bytes):
            string = string.decode('utf-8')
    return string


# FIXME MC_REWRITE_TO_PYTHON: remove after porting all Perl code to Python
def decode_dictionary_from_bytes_if_needed(dictionary):
    new_dictionary = {}
    for k, v in dictionary.items():
        k = decode_string_from_bytes_if_needed(k)
        if isinstance(v, dict):
            new_dictionary[k] = decode_dictionary_from_bytes_if_needed(v)
        else:
            new_dictionary[k] = decode_string_from_bytes_if_needed(v)
    return new_dictionary
