# PostgreSQL backups with WAL-G


## Usage

(To be executed from within a running `postgresql-base` container, e.g. `postgresql-server` or `temporal-postgresql`.)

Make a full backup, or a delta backup if a full backup exists and not more than `WALG_DELTA_MAX_STEPS` delta backups already exist

```bash
# No slash at the end!
wal-g.sh backup-push /var/lib/postgresql/14/main
```

Verify WAL segment storage:

```bash
wal-g.sh wal-verify timeline
# and / or
wal-g.sh wal-verify integrity
```

Leave only two full backups, deleting the rest (including old WALs too):

```bash
# Dry runs by default; add `--confirm` flag to actually delete the old backups
wal-g.sh delete retain FULL 2
```


## S3 bucket configuration

1. Create a bucket:
    1. Name the bucket appropriately, e.g. `mediacloud-postgresql-wal-backups` or `mediacloud-postgresql-wal-backups-test`
    2. Make sure public access to the bucket is off
    3. Add a tag with name `project` and value `mediacloud-postgresql-wal-backups`

2. Create (update) IAM policy:
    1. Name the policy appropriately, e.g. `mediacloud-postgresql-wal-backups` or `mediacloud-postgresql-wal-backups-test`;
    2. Allow access to the previously created bucket, e.g.:

        ```json
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "1",
                    "Effect": "Allow",
                    "Action": [
                        "s3:ListAllMyBuckets"
                    ],
                    "Resource": [
                        "arn:aws:s3:::*"
                    ]
                },
                {
                    "Sid": "2",
                    "Effect": "Allow",
                    "Action": [
                        "s3:ListBucket"
                    ],
                    "Resource": [
                        "arn:aws:s3:::mediacloud-postgresql-wal-backups-test"
                    ]
                },
                {
                    "Sid": "3",
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject"
                    ],
                    "Resource": [
                        "arn:aws:s3:::mediacloud-postgresql-wal-backups-test/*"
                    ]
                }
            ]
        }
        ```

    3. Add a tag with name `project` and value `mediacloud-postgresql-wal-backups`
    4. Describe the project as *TEST ACCOUNT - WAL backups of postgresql-server, temporal-postgresql and possibly others*

3. Create (update) IAM user:
    1. Name the user appropriately, e.g. `mediacloud-postgresql-wal-backups` or `mediacloud-postgresql-wal-backups-test`
    2. Enable only the programmatic access
    3. Attach the newly created / updated policy to the user
    4. Add a tag with name `project` and value `mediacloud-postgresql-wal-backups`


## Links

* <https://wal-g.readthedocs.io/STORAGES/#s3>
