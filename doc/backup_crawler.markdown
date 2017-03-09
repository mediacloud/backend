# Backup crawler

Following are instructions for setting up and running a backup crawler on an AWS machine.

We use a backup crawler for times in which we know that we will or might have to take down the main crawler for more than a few hours. Some of our biggest RSS feeds start scrolling stories off after a few hours, so we risk losing stories during extended crawler down time.

In those cases, we run a temporary version of the crawler that collects only feeds and the URLs found on the feeds. Once the main crawler comes back up, we export the feeds and story URLs from the backup crawler back to the main crawler.

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
        AWS_INSTANCE_NAME="mc-backup-crawler" \
        AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" \
        AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG" \
        AWS_KEYPAIR_NAME="development" \
        AWS_SSH_PRIVKEY="~/development.pem" \
        AWS_SECURITY_GROUP="default" \
        \
        vagrant up --provider=aws &> backup_crawler.log

        # SSH into the newly setup instance
        vagrant ssh

    **Note:** make sure the machine has sufficient disk space. For example, if using AWS, you will need to either create the instance with a large root partition or mount additional storage and use symlinks to get PostgreSQL to use this storage instead of the root partition. At the time of writing, Vagrant sets up EC2 machines with 40 GB of disk space.

    **Note:** make sure to choose a safe EC2 security group (`AWS_SECURITY_GROUP`) for the backup crawler, "safe" meaning that one should allow inly incoming SSH (and maybe ICMP) traffic and nothing else. That's because Media Cloud's `install.sh` creates a demo user `jdoe@mediacloud.org` which could be accessed by anyone from outside.

2. **Make sure that the time zone of your machine is set to Eastern Time.**

    Run `date`, if the result isn't EDT or EST, run:

        sudo dpkg-reconfigure tzdata

    and select `America/New_York`. Additionally, ensure that `America/New_York` is set in `/etc/timezone`.

    **Be aware that AWS machines are often initially setup with UTC as the timezone instead of Eastern.** Vagrant should be able to do this automatically for you.

3. Install Media Cloud on the machine (if it didn't get installed by Vagrant already).

4. On production machine, export `media`, `feeds`, ... table data needed to run a backup crawler:

		production-machine$ ./tools/db/export_import/export_tables_to_backup_crawler.py \
			> mediacloud-dump.sql

5. On backup crawler, create database structure and import table data from production:

		backup-crawler$ createdb mediacloud
		backup-crawler$ psql -f script/mediawords.sql mediacloud
		backup-crawler$ psql -v ON_ERROR_STOP=1 \
			-f mediacloud-dump.sql \
			-d mediacloud

6. Uncomment `rabbitmq` section in `mediawords.yml` under `job_servers`.

7. Start supervisor by running:

        ./supervisor/supervisord.sh

8. Optional: Stop the extractor workers by running:

        ./supervisor/supervisorctl.sh stop extract_and_vector

9. Let the crawler on this machine run as long as desired.

## Exporting

When you're ready to export:

1. Stop the crawler by running:

        ./supervisor/supervisorctl.sh stop mc:crawler

2. On backup crawler, export feed downloads to a CSV file:

		backup-crawler$ ./script/run_with_carton.sh \
			./script/export_import/export_feed_downloads_from_backup_crawler.pl \
			> mediacloud-feed-downloads.csv

3. On production machine, import feed downloads from CSV file:

		production-machine$ ./script/run_with_carton.sh \
			./script/export_import/import_feed_downloads_to_db.pl \
			mediacloud-feed-downloads.csv
