# Temporary crawler

Following are instructions for setting up and running a temporary crawler (backup crawler) on an AWS machine.  We use a temporary crawler
for times in which we know that we will or might have to take down the main crawler for more than a few hours.  Some of
our biggest RSS feeds start scrolling stories off after a few hours, so we risk losing stories during extended crawler
down time.  In those cases, we run a temporary version of the crawler that collects only feeds and the urls found on
the feeds.  Once the main crawler comes back up, we export the feeds and story urls from the temporary crawler
back to the main crawler.

## Setting up

1. Setup a machine with Ubuntu installed, for example, by creating an AWS EC2 instance.

   You might want to consider using [Media Cloud's Vagrant configuration](README.vagrant.markdown) to automate the process. To start a new EC2 Media Cloud instance with 40 GB of disk space, run:

        # Check out a new Media Cloud copy because it will be synced to that EC2 instance
        https://github.com/berkmancenter/mediacloud.git
        cd mediacloud/

        # Check out the release branch because it is more stable and the database schema
        # will be in sync with whatever's running in production
        #
        # Note: the exact name of the release branch might be outdated
        git checkout RELEASE_20140325

        cd script/vagrant/

        # Start EC2 instance, install Media Cloud in it
        #
        # It takes 1-2 hours to set everything up.
        #
        # See doc/README.vagrant.markdown for instructions on how to set the environment
        # variables below.
        AWS_INSTANCE_NAME="mc-temporary-crawler" \
          AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" \
          AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG" \
          AWS_KEYPAIR_NAME="development" \
          AWS_SSH_PRIVKEY="~/development.pem" \
          AWS_SECURITY_GROUP="default" \
          vagrant up --provider=aws &> temporary_crawler.log

        # SSH into the newly setup instance
        vagrant ssh

   **Note:** make sure the machine has sufficient disk space. For example, if using AWS, you will need to either create the instance with a large root partition or mount additional storage and use symlinks to get PostgreSQL to use this storage instead of the root partition. At the time of writing, Vagrant sets up EC2 machines with 40 GB of disk space.

   **Note:** make sure to choose a safe EC2 security group (`AWS_SECURITY_GROUP`) for the temporary crawler, "safe" meaning that one should allow inly incoming SSH (and maybe ICMP) traffic and nothing else. That's because Media Cloud's `install.sh` creates a demo user `jdoe@mediacloud.org` which could be accessed by anyone from outside.

2. **Make sure that the time zone of your machine is set to Eastern Time.**

   Run `date`, if the result isn't EDT or EST, run:

        sudo dpkg-reconfigure tzdata

   and select `America/New_York`.

   **Be aware that AWS machines are often initially setup with UTC as the timezone instead of Eastern.** Vagrant should be able to do this automatically for you.

3. Install Media Cloud on the machine (if it didn't get installed by Vagrant already).

5. Install the Media Cloud API Python client from [https://github.com/c4fcm/MediaCloud-API-Client](https://github.com/c4fcm/MediaCloud-API-Client)

5. `cd` to the Media Cloud installation directory.

   If you are using Vagrant for setting up the machine, Media Cloud is located at `/mediacloud`.

6. Import media and feeds from the production server by running:

        python python_scripts/media_import.py --api-key API-KEY

   where `API-KEY` is an API key for mediacloud.org.

7. Start supervisor by running:

        ./supervisor/supervisord.sh

8. Optional: Stop the extractor workers by running:

        ./supervisor/supervisorctl.sh stop extract_and_vector

9. Let the crawler on this machine run as long as desired.

## Exporting

When you're ready to export:

1. Stop the crawler by running:

        ./supervisor/supervisorctl.sh stop mc:crawler

2. Start the mediacloud server by running:

        ./script/run_server_with_carton.sh

   and leave it running in its own terminal.

3. Find the API key for the local Media Cloud user by running:

        ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
          --action=show \
          --email=jdoe@mediacloud.org

   *Note:* `jdoe@mediacloud.org` is a default demo user created by `./install.sh`.

4. Export `feed_downloads` to the production system by running:

        python python_scripts/export_feed_downloads_through_api.py \
          --source-api-key SOURCE_API_KEY \
          --dest-api-key DEST_API_KEY \
          --source-media-cloud-api_url SOURCE_MEDIA_CLOUD_API_URL \
          --dest-media-cloud-api_url DEST_MEDIA_CLOUD_API_URL

   where:

   * `SOURCE_API_KEY` is the local API key found above,
   * `DEST_API_KEY` is an API key on the Media Cloud server to which you are exporting,
   * `SOURCE_MEDIA_CLOUD_API_URL` is the base URL of the local server from which you are exporting downloads (this will almost always be 'http://localhost:3000/'), and
   * `DEST_MEDIA_CLOUD_API_URL` is the base URL of the server to which you are exporting downloads (this will almost always be `https://api.mediacloud.org/`)

   E.g.:

        python python_scripts/export_feed_downloads_through_api.py \
          --source-api-key 'e07cf98dd0d457351354ee520635c226acd238ecf15ec9e853346e185343bf7b' \
          --dest-api-key '1161251f5de4f381a198eea4dc20350fd992f5eef7cb2fdc284c245ff3d4f3ca' \
          --source-media-cloud-api_url 'http://localhost:3000/' \
          --dest-media-cloud-api_url https://api.mediacloud.org/

5. Verify that this script completed successfully by examining the output.
