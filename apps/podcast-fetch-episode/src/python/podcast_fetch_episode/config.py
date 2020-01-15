from mediawords.util.config import env_value


class PodcastFetchEpisodeConfig(object):
    """
    Podcast episode fetcher configuration.

    Please note that this app should be configured to use Google Cloud service account that must have write access to a
    Cloud Storage bucket for storing the podcast episode audio files.

    For the instructions on creating service accounts, please refer to GoogleCloudConfig class located in
    mediawords.util.config.common. In addition to creating such a service account, you'll additionally have to allow it
    to write to a Cloud Storage bucket:

    1) Enable Cloud Storage API for the project:

        gcloud services enable storage-component.googleapis.com

    2) Create a Cloud Storage bucket to store episode audio files:

        gsutil mb gs://mc-podcast-episodes-audio-files-test

    3) Allow the service account to read / write objects from bucket (here "mc-upload-episode-audio-files" is the
       service account name, and"mc-podcast-transcription-test" is the Google Cloud project ID):

        gsutil acl ch \
            -u mc-upload-episode-audio-files@mc-podcast-transcription-test.iam.gserviceaccount.com:O \
            gs://mc-podcast-episodes-audio-files-test
    """

    @staticmethod
    def gcs_bucket_name() -> str:
        """Return Google Cloud Storage bucket name."""
        return env_value(name='MC_GC_STORAGE_BUCKET_NAME')

    @staticmethod
    def gcs_path_prefix() -> str:
        """Return Google Cloud Storage path prefix under which objects will be stored."""
        return env_value(name='MC_GC_STORAGE_PATH_PREFIX')
