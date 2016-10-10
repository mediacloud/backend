#
# Perl (Inline::Perl) helpers
#


# FIXME remove after porting all Perl code to Python
def decode_string_from_bytes_if_needed(string):
    """Convert 'bytes' string to 'unicode' if needed.
    (http://search.cpan.org/dist/Inline-Python/Python.pod#PORTING_YOUR_INLINE_PYTHON_CODE_FROM_2_TO_3)"""
    if string is not None:
        if isinstance(string, bytes):
            string = string.decode('utf-8')
    return string
