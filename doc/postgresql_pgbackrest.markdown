# PgBackRest


## Usage

A stanza is the [configuration for a PostgreSQL database cluster that defines where it is located, how it will be backed up, archiving options, etc.](https://pgbackrest.org/user-guide.html)

Create stanza:

```bash
pgbackrest --stanza=main stanza-create
```

Check stanza:

```bash
pgbackrest --stanza=main check
```

Do a full backup:

```bash
pgbackrest --stanza=main --type=full backup
```

Do an incremental backup:

```bash
pgbackrest --stanza=main --type=incr backup
```


## Creating S3 bucket

1. Create a bucket:
    1. Name the bucket appropriately, e.g. `mediacloud-pgbackrest` or `mediacloud-pgbackrest-test`
    2. Make sure public access to the bucket is off
    3. Add a tag with name `project` and value `mediacloud-backrest`

2. Create (update) IAM policy:
    1. Name the policy appropriately, e.g. `mediacloud-pgbackrest` or `mediacloud-pgbackrest-test`;
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
                        "arn:aws:s3:::mediacloud-pgbackrest-test"
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
                        "arn:aws:s3:::mediacloud-pgbackrest-test/*"
                    ]
                }
            ]
        }
        ```

    3. Add a tag with name `project` and value `mediacloud-backrest`

3. Create (update) IAM user:
    1. Name the user appropriately, e.g. `mediacloud-pgbackrest` or `mediacloud-pgbackrest-test`
    2. Enable only the programmatic access
    3. Attach the newly created / updated policy to the user
    4. Add a tag with name `project` and value `mediacloud-backrest`
