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


# ---

class McPodcastFetchTranscriptHardException(_AbstractMcPodcastFetchTranscriptException):
    """Hard errors exception."""
    pass


class McMisconfiguredSpeechAPIException(McPodcastFetchTranscriptHardException):
    """Exception thrown when we receive something we didn't expect from Speech API."""
    pass


class McTranscriptionReturnedErrorException(McPodcastFetchTranscriptHardException):
    """
    Exception thrown when Speech API explicitly returns an error state.

    When Speech API returns with an error, it's unclear whether it was us who have messed up or
    something is (temporarily) wrong on their end, so on the safe side we throw a "hard" exception.
    """
    pass
