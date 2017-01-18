class McDatabaseResultException(Exception):
    """Result exception."""
    pass


class McIntInsteadOfBooleanException(McDatabaseResultException):
    """Exception raised on 'column "..." is of type boolean but expression is of type integer'."""

    affected_column = None

    def __init__(self, message, affected_column):
        McDatabaseResultException.__init__(self, message)
        self.affected_column = affected_column


class McDatabaseResultTextException(McDatabaseResultException):
    """text() exception."""
    pass
