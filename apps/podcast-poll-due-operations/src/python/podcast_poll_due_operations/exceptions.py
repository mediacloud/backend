class McPodcastPollDueOperationsHardException(Exception):
    """Hard errors exception."""
    pass


class McDatabaseErrorException(McPodcastPollDueOperationsHardException):
    """Exception thrown when we encounter a database error."""
    pass


class McJobBrokerErrorException(McPodcastPollDueOperationsHardException):
    """Exception thrown when we encounter a job broker (RabbitMQ) error."""
    pass
