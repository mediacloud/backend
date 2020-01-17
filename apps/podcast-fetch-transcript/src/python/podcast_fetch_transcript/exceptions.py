import abc


class _AbstractMcPodcastFetchTranscriptException(Exception, metaclass=abc.ABCMeta):
    """Abstract exception."""
    pass


# ---


class McPodcastFetchTranscriptSoftException(_AbstractMcPodcastFetchTranscriptException):
    """Soft errors exception."""
    pass


class McOperationNotFoundException(_AbstractMcPodcastFetchTranscriptException):
    """Exception thrown when a transcription operation was not found for a particular operation ID."""
    pass


class McOperationStillInProgressException(_AbstractMcPodcastFetchTranscriptException):
    """Exception thrown when a transcription operation is still in progress and we should try later."""
    pass


# ---

class McPodcastFetchTranscriptHardException(_AbstractMcPodcastFetchTranscriptException):
    """Hard errors exception."""
    pass


class McMisconfiguredSpeechAPIException(McPodcastFetchTranscriptHardException):
    """Exception thrown when we receive something we didn't expect from Speech API."""
    pass
