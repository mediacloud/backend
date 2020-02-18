import abc


class _AbstractMcPodcastSubmitOperationException(Exception, metaclass=abc.ABCMeta):
    """Abstract exception."""
    pass


class McPodcastSubmitOperationSoftException(_AbstractMcPodcastSubmitOperationException):
    """Soft errors exception."""
    pass


class McPodcastNoEpisodesException(McPodcastSubmitOperationSoftException):
    """Exception thrown when there are no episodes for a story."""
    pass


class McPodcastEpisodeTooLongException(McPodcastSubmitOperationSoftException):
    """Exception raised when podcast's episode is too long."""
    pass


# ---

class McPodcastSubmitOperationHardException(_AbstractMcPodcastSubmitOperationException):
    """Hard errors exception."""
    pass


class McPodcastDatabaseErrorException(McPodcastSubmitOperationHardException):
    """Exception thrown on database errors."""
    pass


class McPodcastInvalidInputException(McPodcastSubmitOperationHardException):
    """Exception thrown on invalid inputs."""
    pass


class McPodcastMisconfiguredSpeechAPIException(McPodcastSubmitOperationHardException):
    """Exception thrown on misconfigured Google Speech API."""
    pass


class McPodcastSpeechAPIRequestFailedException(McPodcastSubmitOperationHardException):
    """
    Exception that is thrown when we're unable to submit a new job to Speech API.

    This is a hard exception because we should be able to handle "soft" failures (e.g. temporary network errors) of
    Speech API in the code, and on any other, previously unseen, problems (service downtime, ran out of money, blocked,
    outdated API version, etc.) it's better just to shut down the worker
    """
    pass
