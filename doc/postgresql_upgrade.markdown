# PostgreSQL upgrade

To upgrade PostgreSQL between two (e.g. 12 -> 13) or more (e.g. 11 -> 12 -> 13) versions, do the following:


## Preparation (up to a week before)

1. Sync the initial PostgreSQL dataset to a backup server:

    ```bash
    production$ sudo zfs snapshot space/mediacloud/vol_postgresql_data@11_initial

    production$ sudo zfs send space/mediacloud/vol_postgresql_data@11_initial | \
        mbuffer -s 128k -m 10M | \
        pv | \
        ssh backup sudo zfs receive -F space/mediacloud/vol_postgresql_data
    ```

2. Update `apps/postgresql-upgrade/Dockerfile` for it to install the version that you're upgrading *from* and the in-between versions if needed, and then build + push the image.

    You should result with an image that includes all PostgreSQL versions that are needed for upgrading, e.g. if you're upgrading from 11 to 13, `postgresql-upgrade` should include PostgreSQL versions 11, 12 and 13:

    ```dockerfile
    # Parent image already installs PostgreSQL 13
    FROM mc2021/postgresql-server:latest

    # <...>

    RUN \
        #
        # Install PostgreSQL 11 (oldest version)
        apt-get -y --no-install-recommends install \
            postgresql-11 \
            postgresql-client-11 \
            postgresql-contrib-11 \
            postgresql-plperl-11 \
        && \
        #
        # Install PostgreSQL 12 (intermediate version)
        apt-get -y --no-install-recommends install \
            postgresql-12 \
            postgresql-client-12 \
            postgresql-contrib-12 \
            postgresql-plperl-12 \
        && \
        #
        true
    ```

3. Run a test upgrade on a backup server to find out if it works and how long it will take:

    ```bash
    backup$ time docker run -it \
        --shm-size=64g \
        -v /space/mediacloud/vol_postgresql_data:/var/lib/postgresql/ \
        mc2021/postgresql-upgrade \
        postgresql_upgrade.py \
            --source_version=11 \
            --target_version=13 \
        &> test_postgresql_upgrade.log

    backup$ sudo zfs rollback space/mediacloud/vol_postgresql_data@11_initial
    ```

    If it doesn't work, fix the issues on the production server and `zfs send -i old_snapshot new_snapshot` the changes. Rinse and repeat until it works.

    Take note how long it will take for the upgrade script to run.


## Pre-upgrade (a day before)

4. A day or so before the upgrade, create a new dataset snapshot and sync it to the backup server.

    This is done to reduce the time it will require to sync the final snapshot after the database is down for the upgrade.

    ```bash
    production$ sudo zfs snapshot space/mediacloud/vol_postgresql_data@11_intermediate

    production$ sudo zfs send -i \
            space/mediacloud/vol_postgresql_data@11_initial \
            space/mediacloud/vol_postgresql_data@11_intermediate \
        | \
        mbuffer -s 128k -m 10M | \
        pv | \
        ssh backup sudo zfs receive -F space/mediacloud/vol_postgresql_data
    ```


## Upgrade

5. Stop all services:

    ```bash
    docker service rm mediacloud
    ```

    Make sure `postgresql-server` has stopped. If it hasn't, wait for it to stop.

6. Make a final PostgreSQL dataset snapshot and sync it to the backup server:

    ```bash
    production$ sudo zfs snapshot space/mediacloud/vol_postgresql_data@11_final

    production$ sudo zfs send -i \
            space/mediacloud/vol_postgresql_data@11_intermediate \
            space/mediacloud/vol_postgresql_data@11_final \
        | \
        mbuffer -s 128k -m 10M | \
        pv | \
        ssh backup sudo zfs receive -F space/mediacloud/vol_postgresql_data
    ```

7. Run the upgrade script:

    ```bash
    production$ time docker run -it \
        --shm-size=64g \
        -v /space/mediacloud/vol_postgresql_data:/var/lib/postgresql/ \
        mc2021/postgresql-upgrade \
        postgresql_upgrade.py \
            --source_version=11 \
            --target_version=13 \
        &> postgresql_upgrade.log
    ```

8. Create a post-upgrade snapshot:

    ```bash
    production$ sudo zfs snapshot space/mediacloud/vol_postgresql_data@13_initial
    ```

9. Restart all services:

    ```bash
    docker stack deploy -c docker-compose.mediacloud.yml mediacloud
    ```


## Cleanup

10. Copy post-upgrade snapshot to the backup server:

    ```bash
    production$ sudo zfs send -i \
            space/mediacloud/vol_postgresql_data@11_final \
            space/mediacloud/vol_postgresql_data@13_initial \
        | \
        mbuffer -s 128k -m 10M | \
        pv | \
        ssh backup sudo zfs receive -F space/mediacloud/vol_postgresql_data
    ```

11. Clean up pre-upgrade snapshots:

    ```bash
    backup$ zfs destroy space/mediacloud/vol_postgresql_data@11_initial
    backup$ zfs destroy space/mediacloud/vol_postgresql_data@11_intermediate
    backup$ zfs destroy space/mediacloud/vol_postgresql_data@11_final

    production$ zfs destroy space/mediacloud/vol_postgresql_data@11_initial
    production$ zfs destroy space/mediacloud/vol_postgresql_data@11_intermediate
    production$ zfs destroy space/mediacloud/vol_postgresql_data@11_final
    ```
