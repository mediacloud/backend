"""
Custom exceptions used for reporting back various errors back to the workflow.
"""

import abc


# FIXME possibly move these to "common"


class _AbstractPodcastTranscribeEpisodeError(Exception, metaclass=abc.ABCMeta):
    """Abstract exception."""
    pass


class McProgrammingError(_AbstractPodcastTranscribeEpisodeError):
    """
    Exception thrown on programming errors.

    It's pointless to retry actions that have caused this error as we need to fix some code first, and it might be a
    good idea to stop whatever we're doing altogether.

    Examples include:

    * Various third party APIs returning something that our code can't understand.
    * Files existing where they're not supposed to exist.
    * Typos in SQL commands.
    * Assertions.
    """
    pass


class McConfigurationError(_AbstractPodcastTranscribeEpisodeError):
    """
    Exception thrown when something is misconfigured.

    Different from McProgrammingError in that we can figure out that there's a configuration problem somewhere almost
    immediately upon start, while a programming error can take some time to show up (e.g. some sort of an external API
    doesn't work with particular inputs, or the temporary directory can't be written to anymore because we wrote too
    many files in it).

    No reason to retry whatever has caused this error as someone needs to fix the configuration first, and one should
    consider stopping whatever that we're doing as there's no point in continuing without valid configuration anyway.

    Examples include:

    * Configuration environment variables not set / set to invalid values.
    * Bad authentication credentials.
    * Invalid arguments passed.
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


class McPermanentError(_AbstractPodcastTranscribeEpisodeError):
    """
    Exception thrown when some expectations of the application were unmet so it can't proceed with a specific input but
    it's likely that it will be able to process other inputs.

    There's nothing wrong with the code that does the processing, and we can continue on processing other inputs, but
    there's no way to continue processing this particular input or retrying on this error.

    Examples include:

    * One of the stories that's to be processed does not exist at all.
    * HTTP server responding with "404 Not Found".
    * Downloaded media file turns out to not be a media file at all.
    """
    pass
