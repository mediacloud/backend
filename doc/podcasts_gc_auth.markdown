# Google Cloud authentication for podcast transcription

In order to transcribe podcast episodes using Google Cloud's Speech API, you'll need to add a service account which should be able to:

* Read / write objects from / to Google Cloud Storage; and
* Submit transcriptions to and get resulting transcripts from Google Speech-to-text API.


## Creating a service account

1. Create a new Google Cloud project:

    <https://console.cloud.google.com/projectcreate>

2. Install Google Cloud SDK:

    <https://cloud.google.com/sdk/install>

    for example, run:

    ```shell
    brew install google-cloud-sdk
    source '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'
    source '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'
    ```

    on macOS.

3. Log Google Cloud SDK to your Google Cloud account:

    ```shell
    gcloud auth login
    ```

4. Update Google Cloud SDK components, if needed:

    ```shell
    gcloud components update
    ```

5. Choose a default Google Cloud SDK project:

    ```shell
    gcloud config set project PROJECT_ID
    ```

    where `PROJECT_ID` is your Google Cloud project ID which can be found in:

    <https://console.cloud.google.com/iam-admin/settings>

7. Enable Cloud Storage API for the project:

    ```shell
    gcloud services enable storage-component.googleapis.com
    ```

8. Enable Speech API for the project:

    ```shell
    gcloud services enable speech.googleapis.com
    ```

9. Create three Cloud Storage buckets:

    ```shell
    # Raw (non-transcoded) enclosures fetched from podcast websites
    gsutil mb gs://mc-podcast-raw-enclosures-test

    # Transcoded episodes ready for submission to the Speech API
    gsutil mb gs://mc-podcast-transcoded-episodes-test

    # Transcript JSON files
    gsutil mb gs://mc-podcast-transcripts-test
    ```

10. Create a lifecycle policy to move audio objects (but not the JSON transcripts!) to Archive storage class after one month:

    ```shell
    cat << EOF > /var/tmp/gs-lifecycle.json
    {
        "rule": [
            {
                "action": {
                    "storageClass": "ARCHIVE",
                    "type": "SetStorageClass"
                },
                "condition": {
                    "age": 30
                }
            }
        ]
    }
    EOF

    gsutil lifecycle set /var/tmp/gs-lifecycle.json gs://mc-podcast-transcoded-episodes-test
    gsutil lifecycle set /var/tmp/gs-lifecycle.json gs://mc-podcast-raw-enclosures-test
    # "mc-podcast-transcripts-test" has a bunch of tiny objects so they can
    # remain in Standart storage class

    rm /var/tmp/gs-lifecycle.json

    ```

11. Create a service account that the podcast transcribing workflow will use:

    ```shell
    gcloud iam service-accounts create mc-transcribe-podcasts-test \
        --display-name="(test) Transcribe story-derived podcasts" \
        --description="(test) Upload episodes to GCS, submit them to Speech API, fetch transcripts"
    ```

12. Allow the service account to read / write objects from buckets (here `mc-upload-episode-audio-files` is the service account name, and `mc-podcast-transcription-test` is the Google Cloud project ID):

    ```shell
    gsutil acl ch \
        -u mc-transcribe-podcasts-test@meag-podcast-transcription-tst.iam.gserviceaccount.com:O \
        gs://mc-podcast-raw-enclosures-test
    gsutil acl ch \
        -u mc-transcribe-podcasts-test@meag-podcast-transcription-tst.iam.gserviceaccount.com:O \
        gs://mc-podcast-transcoded-episodes-test
    gsutil acl ch \
        -u mc-transcribe-podcasts-test@meag-podcast-transcription-tst.iam.gserviceaccount.com:O \
        gs://mc-podcast-transcripts-test
    ```

13. Generate authentication JSON credentials:

    ```shell
    gcloud iam service-accounts keys create \
        mc-transcribe-podcasts-test.json \
        --iam-account mc-transcribe-podcasts-test@meag-podcast-transcription-tst.iam.gserviceaccount.com
    ```

14. Encode contents of `mc-transcribe-podcasts-test.json` to Base64:

    ```shell
    base64 mc-transcribe-podcasts-test.json
    ```

15. Copy the resulting Base64-encoded string to `MC_PODCAST_AUTH_JSON_BASE64` environment variable that's set for apps using Google Cloud services for podcast transcription.
