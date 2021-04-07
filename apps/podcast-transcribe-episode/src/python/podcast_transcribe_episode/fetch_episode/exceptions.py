import abc


class _AbstractMcPodcastFetchEpisodeException(Exception, metaclass=abc.ABCMeta):
    """Abstract exception."""
    pass


class McPodcastFetchEpisodeSoftException(_AbstractMcPodcastFetchEpisodeException):
    """Soft errors exception."""
    pass


class McStoryNotFoundException(McPodcastFetchEpisodeSoftException):
    """Exception raised when story was not found."""
    pass


class McPodcastNoViableStoryEnclosuresException(McPodcastFetchEpisodeSoftException):
    """Exception thrown when story has no viable enclosures to choose from."""
    pass


class McPodcastEnclosureTooBigException(McPodcastFetchEpisodeSoftException):
    """Exception thrown when story's best viable enclosure is too big."""
    pass


class McPodcastFileFetchFailureException(McPodcastFetchEpisodeSoftException):
    """Exception thrown when we're unable to fetch the downloaded file for whatever reason."""
    pass


class McPodcastFileIsInvalidException(McPodcastFetchEpisodeSoftException):
    """Exception thrown when the fetched file is not something that we can process for whatever reason."""
    pass


# ---

class McPodcastFetchEpisodeHardException(_AbstractMcPodcastFetchEpisodeException):
    """Hard errors exception."""
    pass


class McPodcastFileStoreFailureException(McPodcastFetchEpisodeHardException):
    """
    Exception thrown when we're unable to store the downloaded file for whatever reason.

    This is a hard exception as not being able to store a file means that we might be out of disk space or something
    like that.
    """
    pass


class McPodcastGCSStoreFailureException(McPodcastFetchEpisodeHardException):
    """
    Exception thrown when we're unable to store an object to Google Cloud Storage.

    GCS problems, if any, are probably temporary, but still, in those cases we should retry a few times and then give up
    permanently because not being able to store stuff to GCS might mean that we ran out of some sort of a limit,
    credentials are wrong, etc.
    """
    pass


class McPodcastMisconfiguredTranscoderException(McPodcastFetchEpisodeHardException):
    """Exception thrown when something happens with the transcoder that we didn't anticipate before."""
    pass


class McPodcastMisconfiguredGCSException(McPodcastFetchEpisodeHardException):
    """Exception thrown when something happens with Google Cloud Storage that we didn't anticipate before."""
    pass


class McPodcastPostgreSQLException(McPodcastFetchEpisodeHardException):
    """Exception thrown on PostgreSQL errors."""
    pass
