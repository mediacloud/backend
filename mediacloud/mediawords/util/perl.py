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
def decode_object_from_bytes_if_needed(obj):
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
