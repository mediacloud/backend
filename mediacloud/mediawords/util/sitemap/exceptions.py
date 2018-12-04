class McSitemapsException(Exception):
    """Problem due to which we can't run further, e.g. wrong input parameters."""
    pass


class McSitemapsXMLParsingException(Exception):
    """XML parsing exception to be handled gracefully."""
    pass
