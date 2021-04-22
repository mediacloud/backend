import abc


class _AbstractPodcastTranscribeEpisodeException(Exception, metaclass=abc.ABCMeta):
    """Abstract exception."""
    pass


class SoftException(_AbstractPodcastTranscribeEpisodeException):
    """Soft errors exception."""
    pass


class McPodcastFileFetchFailureException(SoftException):
    """Exception thrown when we're unable to fetch the downloaded file for whatever reason."""
    pass


class McPodcastFileIsInvalidException(SoftException):
    """Exception thrown when the fetched file is not something that we can process for whatever reason."""
    pass


# ---

class HardException(_AbstractPodcastTranscribeEpisodeException):
    """Hard errors exception."""
    pass


class McPodcastFileStoreFailureException(HardException):
    """
    Exception thrown when we're unable to store the downloaded file for whatever reason.

    This is a hard exception as not being able to store a file means that we might be out of disk space or something
    like that.
    """
    pass


class McPodcastGCSStoreFailureException(HardException):
    """
    Exception thrown when we're unable to store an object to Google Cloud Storage.

    GCS problems, if any, are probably temporary, but still, in those cases we should retry a few times and then give up
    permanently because not being able to store stuff to GCS might mean that we ran out of some sort of a limit,
    credentials are wrong, etc.
    """
    pass


class McPodcastMisconfiguredTranscoderException(HardException):
    """Exception thrown when something happens with the transcoder that we didn't anticipate before."""
    pass


class McPodcastMisconfiguredGCSException(HardException):
    """Exception thrown when something happens with Google Cloud Storage that we didn't anticipate before."""
    pass


class McDatabaseNotFoundException(HardException):
    """Exception thrown when we can't find something in the database that we've expected to find."""
    pass


class McMisconfiguredSpeechAPIException(HardException):
    """Exception thrown when we receive something we didn't expect from Speech API."""
    pass


class McPodcastDatabaseErrorException(HardException):
    """Exception thrown on database errors."""
    pass


class McPodcastInvalidInputException(HardException):
    """Exception thrown on invalid inputs."""
    pass


class McPodcastMisconfiguredSpeechAPIException(HardException):
    """Exception thrown on misconfigured Google Speech API."""
    pass


class McPodcastSpeechAPIRequestFailedException(HardException):
    """
    Exception that is thrown when we're unable to submit a new job to Speech API.

    This is a hard exception because we should be able to handle "soft" failures (e.g. temporary network errors) of
    Speech API in the code, and on any other, previously unseen, problems (service downtime, ran out of money, blocked,
    outdated API version, etc.) it's better just to shut down the worker
    """
    pass
