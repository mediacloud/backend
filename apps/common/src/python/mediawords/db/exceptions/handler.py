class McDatabaseHandlerException(Exception):
    """Database handler exception."""
    pass


class McConnectException(McDatabaseHandlerException):
    """__connect() exception."""
    pass


class McQueryException(McDatabaseHandlerException):
    """query() exception."""
    pass


class McTransactionRollbackError(McQueryException):
    """Error causing transaction rollback (deadlocks, serialization failures, etc.)"""
    pass


class McTupleAlreadyMovedError(McTransactionRollbackError):
    """Error thrown on 'tuple to be locked was already moved to another partition due to concurrent update' error."""
    pass


class McPrimaryKeyColumnException(McDatabaseHandlerException):
    """primary_key_column() exception."""
    pass


class McFindByIDException(McDatabaseHandlerException):
    """find_by_id() exception."""
    pass


class McRequireByIDException(McDatabaseHandlerException):
    """require_by_id() exception."""
    pass


class McUpdateByIDException(McDatabaseHandlerException):
    """update_by_id() exception."""
    pass


class McDeleteByIDException(McDatabaseHandlerException):
    """delete_by_id() exception."""
    pass


class McCreateException(McDatabaseHandlerException):
    """create() exception."""
    pass


class McUniqueConstraintException(McDatabaseHandlerException):
    """create() exception."""
    pass


class McFindOrCreateException(McDatabaseHandlerException):
    """find_or_create() exception."""
    pass


class McQuoteException(McDatabaseHandlerException):
    """quote() exception."""
    pass


class McPrepareException(McDatabaseHandlerException):
    """prepare() exception."""
    pass


class McTransactionException(McDatabaseHandlerException):
    """Exception thrown on transaction problems."""
    pass


class McBeginException(McTransactionException):
    """begin() exception."""
    pass
