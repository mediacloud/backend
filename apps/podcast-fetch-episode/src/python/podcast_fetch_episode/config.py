import hashlib
import os
import tempfile

from mediawords.util.config import env_value
from mediawords.util.parse_json import decode_json


class PodcastFetchEpisodeConfig(object):
    """podcast-fetch-episode configuration."""

    @staticmethod
    def gcs_bucket_name() -> str:
        """Return Google Cloud Storage bucket name."""
        return env_value(name='MC_GCS_BUCKET_NAME')

    @staticmethod
    def gcs_path_prefix() -> str:
        """Return Google Cloud Storage path prefix under which objects will be stored."""
        return env_value(name='MC_GCS_PATH_PREFIX')

    @staticmethod
    def gcs_application_credentials_json_path() -> str:
        """
        Path to autentication credentials JSON file for connecting to Google Cloud Storage.

        Reads the configuration from environment file, writes it to a temporary file (if it doesn't exist yet),
        returns its path.

        To get the JSON file with authentication credentials, you need to create both a bucket to store raw audio files
        and a service account that would have a permission to access said bucket:

        1) Create a new Google Cloud project:

            https://console.cloud.google.com/projectcreate

        2) Install Google Cloud SDK:

            https://cloud.google.com/sdk/install

        for example, run:

            brew install google-cloud-sdk
            source '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'
            source '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'

        on macOS.

        3) Log Google Cloud SDK to your Google Cloud account:

            gcloud auth login

        4) Update Google Cloud SDK components, if needed:

            gcloud components update

        5) Choose a default Google Cloud SDK project:

            gcloud config set project PROJECT_ID

        where PROJECT_ID is your Google Cloud project ID which can be found in:

            https://console.cloud.google.com/iam-admin/settings

        6) Enable Speech API for the project:

            gcloud services enable speech.googleapis.com

        7) Enable Cloud Storage API for the project:

            gcloud services enable storage-component.googleapis.com

        8) Create a Cloud Storage bucket to store episode audio files:

            gsutil mb gs://mc-podcast-episodes-audio-files-test

        9) Create a service account for uploading episode audio files:

            gcloud iam service-accounts create mc-upload-episode-audio-files \
                --display-name="Upload episode audio files" \
                --description="Used to upload podcast episode audio files"

        10) Allow the newly created service account to read / write objects from bucket
        (here "mc-podcast-transcription-test" is the Google Cloud project ID):

            gsutil acl ch \
                -u mc-upload-episode-audio-files@mc-podcast-transcription-test.iam.gserviceaccount.com:O \
                gs://mc-podcast-episodes-audio-files-test

        11) Generate authentication JSON credentials:

            gcloud iam service-accounts keys create \
                mc-podcast-episodes-audio-files-test.json \
                --iam-account mc-upload-episode-audio-files@mc-podcast-transcription-test.iam.gserviceaccount.com

        12) Copy contents of "mc-podcast-episodes-audio-files-test.json" to MC_GCS_CREDENTIALS_JSON_STRING environment
        variable.

        :return: Path to authentication credentials JSON file to use for from_service_account_json().
        """
        json_string = env_value(name='MC_GCS_CREDENTIALS_JSON_STRING')

        # Try decoding
        decode_json(json_string)

        json_string_sha1 = hashlib.sha1(json_string.encode('utf-8')).hexdigest()
        json_path = os.path.join(tempfile.gettempdir(), f"{json_string_sha1}.json")

        if not os.path.isfile(json_path):
            with open(json_path, mode='w') as f:
                f.write(json_string)

        return json_path
