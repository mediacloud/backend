import abc


class _AbstractPodcastTranscribeEpisodeException(Exception, metaclass=abc.ABCMeta):
    """Abstract exception."""
    pass


class PodcastTranscribeEpisodeSoftException(_AbstractPodcastTranscribeEpisodeException):
    """Soft errors exception."""
    pass


class McStoryNotFoundException(PodcastTranscribeEpisodeSoftException):
    """Exception raised when story was not found."""
    pass


class McPodcastNoViableStoryEnclosuresException(PodcastTranscribeEpisodeSoftException):
    """Exception thrown when story has no viable enclosures to choose from."""
    pass


class McPodcastEnclosureTooBigException(PodcastTranscribeEpisodeSoftException):
    """Exception thrown when story's best viable enclosure is too big."""
    pass


class McPodcastFileFetchFailureException(PodcastTranscribeEpisodeSoftException):
    """Exception thrown when we're unable to fetch the downloaded file for whatever reason."""
    pass


class McPodcastFileIsInvalidException(PodcastTranscribeEpisodeSoftException):
    """Exception thrown when the fetched file is not something that we can process for whatever reason."""
    pass


class McOperationNotFoundException(PodcastTranscribeEpisodeSoftException):
    """Exception thrown when a transcription operation was not found for a particular operation ID."""
    # Not a "hard" failure as sometimes these operations expire
    pass


class McPodcastNoEpisodesException(PodcastTranscribeEpisodeSoftException):
    """Exception thrown when there are no episodes for a story."""
    pass


class McPodcastEpisodeTooLongException(PodcastTranscribeEpisodeSoftException):
    """Exception raised when podcast's episode is too long."""
    pass


# ---

class PodcastTranscribeEpisodeHardException(_AbstractPodcastTranscribeEpisodeException):
    """Hard errors exception."""
    pass


class McPodcastFileStoreFailureException(PodcastTranscribeEpisodeHardException):
    """
    Exception thrown when we're unable to store the downloaded file for whatever reason.

    This is a hard exception as not being able to store a file means that we might be out of disk space or something
    like that.
    """
    pass


class McPodcastGCSStoreFailureException(PodcastTranscribeEpisodeHardException):
    """
    Exception thrown when we're unable to store an object to Google Cloud Storage.

    GCS problems, if any, are probably temporary, but still, in those cases we should retry a few times and then give up
    permanently because not being able to store stuff to GCS might mean that we ran out of some sort of a limit,
    credentials are wrong, etc.
    """
    pass


class McPodcastMisconfiguredTranscoderException(PodcastTranscribeEpisodeHardException):
    """Exception thrown when something happens with the transcoder that we didn't anticipate before."""
    pass


class McPodcastMisconfiguredGCSException(PodcastTranscribeEpisodeHardException):
    """Exception thrown when something happens with Google Cloud Storage that we didn't anticipate before."""
    pass


class McPodcastPostgreSQLException(PodcastTranscribeEpisodeHardException):
    """Exception thrown on PostgreSQL errors."""
    pass


class McDatabaseNotFoundException(PodcastTranscribeEpisodeHardException):
    """Exception thrown when we can't find something in the database that we've expected to find."""
    pass


class McDatabaseErrorException(PodcastTranscribeEpisodeHardException):
    """Exception thrown when a database raises an error."""
    pass


class McMisconfiguredSpeechAPIException(PodcastTranscribeEpisodeHardException):
    """Exception thrown when we receive something we didn't expect from Speech API."""
    pass


class McTranscriptionReturnedErrorException(PodcastTranscribeEpisodeHardException):
    """
    Exception thrown when Speech API explicitly returns an error state.

    When Speech API returns with an error, it's unclear whether it was us who have messed up or
    something is (temporarily) wrong on their end, so on the safe side we throw a "hard" exception.
    """
    pass


class McPodcastDatabaseErrorException(PodcastTranscribeEpisodeHardException):
    """Exception thrown on database errors."""
    pass


class McPodcastInvalidInputException(PodcastTranscribeEpisodeHardException):
    """Exception thrown on invalid inputs."""
    pass


class McPodcastMisconfiguredSpeechAPIException(PodcastTranscribeEpisodeHardException):
    """Exception thrown on misconfigured Google Speech API."""
    pass


class McPodcastSpeechAPIRequestFailedException(PodcastTranscribeEpisodeHardException):
    """
    Exception that is thrown when we're unable to submit a new job to Speech API.

    This is a hard exception because we should be able to handle "soft" failures (e.g. temporary network errors) of
    Speech API in the code, and on any other, previously unseen, problems (service downtime, ran out of money, blocked,
    outdated API version, etc.) it's better just to shut down the worker
    """
    pass
