import abc


# FIXME possibly move these to "common"


class _AbstractPodcastTranscribeEpisodeError(Exception, metaclass=abc.ABCMeta):
    """Abstract exception."""
    pass


class McConfigurationError(_AbstractPodcastTranscribeEpisodeError):
    """
    Exception thrown when something is misconfigured.

    No reason to retry whatever has caused this error as someone needs to fix the configuration first, and one should
    consider stopping whatever that we're doing as there's no point in continuing without valid configuration anyway.

    Examples include:

    * Configuration environment variables not set / set to invalid values.
    * Bad authentication credentials.
    * Invalid arguments passed.
    """
    pass


class McProgrammingError(_AbstractPodcastTranscribeEpisodeError):
    """
    Exception thrown on programming errors.

    It's pointless to retry actions that have caused this error as we need to fix some code first, and it might be a
    good idea to stop whatever we're doing altogether with something like fatal_error(...).

    Examples include:

    * Various third party APIs returning something that our code can't understand.
    * Files existing where they're not supposed to exist.
    * Typos in SQL commands.
    * Assertions.
    """
    pass


class McTransientError(_AbstractPodcastTranscribeEpisodeError):
    """
    Exception thrown on transient (occurring at irregular intervals) errors.

    It is reasonable to expect that when this error occurs, we can wait for a bit, retry and the action might succeed.

    Examples include:

    * Not being able to connect to the database.
    * HTTP server responding with "503 Service Unavailable".
    * Network being down.
    """
    pass


class McSoftAppError(_AbstractPodcastTranscribeEpisodeError):
    """
    Exception thrown when some expectations of the application were unmet so it can't proceed with a specific input but
    it's likely that it will be able to continue on with other inputs.

    There's nothing wrong with the code that does the processing, and we can continue on processing other inputs, but
    there's no point in retrying on this error.

    Examples include:

    * One of the stories that's to be processed does not exist at all.
    * HTTP server responding with "404 Not Found".
    * Downloaded media file turns out to not be a media file at all.
    """
    pass


class McHardAppError(_AbstractPodcastTranscribeEpisodeError):
    """
    Exception thrown when some expectations of the application were unmet, and so the whole application can't proceed
    further due to those expectations being unmet.

    Examples include:

    * A single story that was passed as an argument and had to be processed doesn't exist.
    * We've tried fetching 10k links, and 90% of links failed at getting fetched.
    """
    pass


class SoftException(_AbstractPodcastTranscribeEpisodeError):
    """Soft errors exception."""
    pass


class McPodcastFileIsInvalidException(SoftException):
    """Exception thrown when the fetched file is not something that we can process for whatever reason."""
    pass


# ---

class HardException(_AbstractPodcastTranscribeEpisodeError):
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
