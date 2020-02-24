import abc


class AbstractMcCrawlerFetcherException(Exception, metaclass=abc.ABCMeta):
    pass


class McCrawlerFetcherSoftError(AbstractMcCrawlerFetcherException):
    """Soft errors on which we can continue crawling other downloads."""
    pass


class McCrawlerFetcherHardError(AbstractMcCrawlerFetcherException):
    """Hard errors on which we should stop crawling all downloads."""
    pass
