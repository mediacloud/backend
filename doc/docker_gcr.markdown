# Creating service account for pushing Docker images from CI to Container Registry

1. Create a new Google Cloud project:

    <https://console.cloud.google.com/projectcreate>

2. Install Google Cloud SDK:

    <https://cloud.google.com/sdk/install>

3. Log Google Cloud SDK to your Google Cloud account:

    ```shell
    gcloud auth login
    ```

4. Choose a default Google Cloud SDK project:

    ```shell
    gcloud config set project mcback
    ```

5. Enable Container Registry API for the project:

    ```shell
    gcloud services enable containerregistry.googleapis.com
    ```

6. Create a service account that the podcast transcribing apps would use:

    ```shell
    gcloud iam service-accounts create mc-ci-push-docker-images \
        --display-name="Push Docker images" \
        --description="Push CI-build Docker images to GCR"
    ```

7. Allow the service account to read / write objects from bucket with Container Registry artifacts:

    ```shell
    gsutil acl ch \
        -u \
        mc-ci-push-docker-images@mcback.iam.gserviceaccount.com:W \
        gs://artifacts.mcback.appspot.com/
    ```

8. Generate authentication JSON credentials:

    ```shell
    gcloud iam service-accounts keys create \
        mc-ci-push-docker-images.json \
        --iam-account mc-ci-push-docker-images@mcback.iam.gserviceaccount.com
    ```

9. Copy the resulting file into GitHub project secret under `DOCKER_GCR_SERVICE_ACCOUNT` name.
