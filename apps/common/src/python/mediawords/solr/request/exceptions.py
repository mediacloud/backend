import abc


class _AbstractSolrRequestException(Exception, metaclass=abc.ABCMeta):
    """Abstract .solr.request exception."""
    pass


class _AbstractSolrRequestConnectionErrorException(_AbstractSolrRequestException):
    """Problems with Solr connectivity."""
    pass


class McSolrRequestDidNotStartInTimeException(_AbstractSolrRequestConnectionErrorException):
    """Exception thrown when Solr didn't manage to start in time."""
    pass


class _AbstractSolrRequestQueryErrorException(_AbstractSolrRequestException):
    """Problems with Solr query."""
    pass


class McSolrRequestQueryErrorException(_AbstractSolrRequestQueryErrorException):
    """Solr query failed."""
    pass


class McSolrRequestInvalidParamsException(_AbstractSolrRequestQueryErrorException):
    """solr_request() received invalid parameters."""
    pass
