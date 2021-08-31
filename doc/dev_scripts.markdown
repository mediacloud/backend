<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [Developer scripts](#developer-scripts)
      * [pull.py - pull images](#pullpy---pull-images)
         * [Usage](#usage)
      * [build.py - build images](#buildpy---build-images)
         * [Usage](#usage-1)
      * [push.py - push images](#pushpy---push-images)
         * [Usage](#usage-2)
      * [run.py - run command in app's testing environment](#runpy---run-command-in-apps-testing-environment)
         * [Usage](#usage-3)
      * [run_test.py - run test in app's testing environment](#run_testpy---run-test-in-apps-testing-environment)
         * [Usage](#usage-4)
      * [run_all_tests.py - run all tests in their respective app's testing environments](#run_all_testspy---run-all-tests-in-their-respective-apps-testing-environments)
         * [Usage](#usage-5)
      * [print_docker_run_in_stack.py - print <code>docker run</code> command that would join the production stack](#print_docker_run_in_stackpy---print-docker-run-command-that-would-join-the-production-stack)
         * [Usage](#usage-6)

----
<!-- MEDIACLOUD-TOC-END -->


# Developer scripts

While you can get away with using vanilla Docker and running `docker` and `docker-compose` commands yourself, a bunch of developer scripts available under `dev/` should make it easier to do common everyday tasks.

Every script supports a `-h` argument which prints some rudimentary description on how to use the script.

Also, almost every script (`print_docker_run_in_stack.py` being a notable exception) has `-p` argument which, when passed, will print Docker or Docker Compose commands that are to be run instead of running them itself. This might be useful for:

* **Debugging and learning** - `./dev/run.py -p common bash` would print a list of Docker Compose commands that would set up a new Compose environment using `common`'s `docker-compose.tests.yml`, run `bash` in it, and lastly destroy said environment.
* **Cherry-picking which commands to run** - `./dev/pull.py -p | grep solr` will print a list of commands to pull only the container images that have a string `solr` in their name; `./dev/pull.py -p | grep solr | bash` would run the commands instead of just printing them.
* **Parallelizing tests** - `./dev/run_all_tests.py -p | parallel` would print a list of commands to run every Perl and Python test found in the test suite; said list would be piped to the `parallel` utility which would then run all of those commands in parallel.

## `pull.py` - pull images

`pull.py` pulls pre-built images for every app, tagged with the name of the current Git branch. For example, if you're currently in the `feature-xyz` Git branch, the script will attempt to pull `gcr.io/mcback/<app_name>:feature-xyz` images for every app.

If an image tagged with the Git branch name doesn't exist (e.g. your branch is new and hasn't been built yet, or the image build for the branch never completed successfully), script will attempt to pull images tagged with `master` (i.e. the images that were built from the `master` Git branch).

If the script manages to pull an image for an app (either from the feature branch or from `master`), it gets tagged with both the branch name (if such a tag doesn't exist yet) and `latest` tag locally.

### Usage

To pull the latest build of every image of the current Git branch, run:

```bash
$ ./dev/pull.py
```

After pulling the images, your Docker instance will end up having images for every app, tagged with both the Git branch name and `latest`:

```bash
$ docker images
REPOSITORY                             TAG         IMAGE ID      CREATED     SIZE
<...>
gcr.io/mcback/postgresql-pgbouncer  containers  46d1ed5fd590  4 days ago  202MB
gcr.io/mcback/postgresql-pgbouncer  latest      46d1ed5fd590  4 days ago  202MB
gcr.io/mcback/postgresql-server     containers  42fbeb4f9fa9  9 days ago  482MB
gcr.io/mcback/postgresql-server     latest      42fbeb4f9fa9  9 days ago  482MB
gcr.io/mcback/postgresql-base       containers  553371ddd833  9 days ago  198MB
gcr.io/mcback/postgresql-base       latest      553371ddd833  9 days ago  198MB
```

While the initial pull might take a while (because there's a lot of data to download), any subsequent pulls should take just a couple of seconds as the script will then download only the Docker image layers that it doesn't have.

This script can print the commands that are going to be run instead of running them itself if you pass it the `-p` argument. You can use this capability to filter the list of images that are going to be pulled, e.g.:

```bash
# Pull only images with "solr-shard" string in their name
$ ./dev/pull.py -p | grep solr-shard | bash

# Pull everything *except* for the large "nytlabels-annotator" image
$ ./dev/pull.py -p | grep -v nytlabels-annotator | bash
```

## `build.py` - build images

(Re-)build Docker images for all apps, and tag them with both the name of the current Git branch and `latest`.

Before (re-)building the container images, you might want to pull them first using the `pull.py` script. The build script will attempt to reuse cache from pulled pre-built images. If nothing has changed in the source code or the dependencies of the apps, the build script will be able to reuse build layers from the pre-built image, and so building images of all the apps could take only up to 30 seconds.

### Usage

To build every app and tag the built images with the name of the current Git branch, run:

```bash
$ ./dev/build.py
```

Similarly to `pull.py` script, this script can print the commands that are going to be run instead of running them itself if you pass it the `-p` argument. You can use this capability to filter the list of images that are going to be built, e.g.:

```bash
# Build only images with "solr-shard" string in their name
# (pipe to "bash -e" to stop on the first build error)
$ ./dev/build.py -p | grep solr-shard | bash -e
```

## `push.py` - push images

Push all local images tagged with the current Git branch name to container repository.

### Usage

To push every container image tagged with current Git branch name to container repository, run:

```bash
$ ./dev/push.py
```

Similarly to `pull.py` script, this script can print the commands that are going to be run instead of running them itself if you pass it the `-p` argument. You can use this capability to filter the list of images that are going to be pushed, e.g.:

```bash
# Push only images with "solr-shard" string in their name
# (pipe to "bash -e" to stop on the first push error)
$ ./dev/push.py -p | grep solr-shard | bash -e
```

## `run.py` - run command in app's testing environment

Set up app's testing environment as specified in `docker-compose.tests.yml`, start all the containers in said environment, and run an arbitrary command in the main app container of the testing environment. After the command completes, clean everything up and return the exit code of the command that was run in the main container.

### Usage

To set up `import-solr-data` app's testing environment (as defined in `import-solr-data/docker-compose.tests.yml`) and run `bash` in the main `import-solr-data` container, run:

```bash
$ ./dev/run.py import-solr-data bash
```

The script will then start the main `import-solr-data`, all its dependencies, and finally will run `bash` in the main container:

```bash
$ ./dev/run.py import-solr-data bash
Creating network "mc-import-solr-data-bash_default" with the default driver
Creating mc-import-solr-data-bash_postgresql-server_1 ... done
Creating mc-import-solr-data-bash_rabbitmq-server_1   ... done
Creating mc-import-solr-data-bash_solr-zookeeper_1    ... done
Creating mc-import-solr-data-bash_solr-shard-01_1        ... done
Creating mc-import-solr-data-bash_postgresql-pgbouncer_1 ... done
Creating mc-import-solr-data-bash_import-solr-data-for-testing_1 ... done
mediacloud@884c21ca6997:/$ 
```

All the dependency containers will be accessible from this newly started development environment:

```bash
mediacloud@884c21ca6997:/$ ping -c 1 solr-shard-01
PING solr-shard-01 (172.23.0.6) 56(84) bytes of data.
64 bytes from mc-import-solr-data-bash_solr-shard-01_1.mc-import-solr-data-bash_default (172.23.0.6): icmp_seq=1 ttl=64 time=0.124 ms

--- solr-shard-01 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.124/0.124/0.124/0.000 ms
```

After the main command passed as an argument to the script finishes, the script will stop and remove all the test containers together with their data (if any):

```bash
mediacloud@884c21ca6997:/$ exit 0
exit
Stopping mc-import-solr-data-bash_import-solr-data-for-testing_1 ... done
Stopping mc-import-solr-data-bash_postgresql-pgbouncer_1         ... done
Stopping mc-import-solr-data-bash_solr-shard-01_1                ... done
Stopping mc-import-solr-data-bash_solr-zookeeper_1               ... done
Stopping mc-import-solr-data-bash_postgresql-server_1            ... done
Stopping mc-import-solr-data-bash_rabbitmq-server_1              ... done
Removing mc-import-solr-data-bash_import-solr-data-for-testing_1 ... done
Removing mc-import-solr-data-bash_postgresql-pgbouncer_1         ... done
Removing mc-import-solr-data-bash_solr-shard-01_1                ... done
Removing mc-import-solr-data-bash_solr-zookeeper_1               ... done
Removing mc-import-solr-data-bash_postgresql-server_1            ... done
Removing mc-import-solr-data-bash_rabbitmq-server_1              ... done
Removing network mc-import-solr-data-bash_default

$ docker ps -a -q
$ 
```

To pass arguments to the command that is to be run in the main container, prefix the whole command with `--`:

```bash
$ ./dev/run.py common -- py.test -s -v /opt/mediacloud/tests/python/mediawords/test_db.py
```

Similarly to `pull.py` script, this script can print the commands that are going to be run instead of running them itself if you pass it the `-p` argument. You can use this capability for debugging purposes.

## `run_test.py` - run test in app's testing environment

Set up app's testing environment as specified in `docker-compose.tests.yml`, start all the containers in said environment, and run tests from a Perl / Python test file in the main app container of the testing environment. After the command completes, clean everything up and return the exit code of the command that was run in the main container.

### Usage

To run a single Python test located at `apps/common/tests/python/mediawords/test_db.py` in the Git repository, run:

```bash
$ ./dev/run_test.py apps/common/tests/python/mediawords/test_db.py
```

Similarly, to run a single Perl test located at `apps/common/tests/perl/MediaWords/Solr.t` in the Git repository, run:

```bash
$ ./dev/run_test.py apps/common/tests/perl/MediaWords/Solr.t
```

Similarly to `pull.py` script, this script can print the commands that are going to be run instead of running them itself if you pass it the `-p` argument. You can use this capability for debugging purposes.

## `run_all_tests.py` - run all tests in their respective app's testing environments

Find all Perl / Python test files of all the apps, and run tests of all found files in their respective app's testing environments.

### Usage

To run all the tests in all the test files of all the apps, run:

```shell
$ ./dev/run_all_tests.py
```

Similarly to `pull.py` script, this script can print the commands that are going to be run instead of running them itself if you pass it the `-p` argument. You can use this capability to pick out which specific tests to run:

```bash
# Run all the tests from the "common" app (the ones which have "/app/common/" as part of their path)
$ ./dev/run_all_tests.py -p | grep /apps/common/ | bash
```

and / or to parallelize tests with `parallel` utility:

```bash
# Print all commands to run all the tests, and pipe them to "parallel" which will run them in
# parallel, running up to 4 commands at the same time, grouping the output, and logging the outcome
# of every command to "joblog.txt"
$ ./dev/run_all_tests.py -p | parallel --jobs 4 --group --joblog joblog.txt
```


## `print_docker_run_in_stack.py` - print `docker run` command that would join the production stack

Print a `docker run` command that would:

* Start a new container using a given service's image name and production environment variables;
* Join said container to the production Docker stack.

### Usage

To get a command that would start a new container using `topics-mine` image (assuming that your production `docker-compose.yml` is available at `~/production-docker-config/docker-compose.yml`), run:

```shell
$ ./dev/print_docker_run_in_stack.py ~/production-docker-config/docker-compose.yml topics-mine
```

which will then print:

```
Here's a "docker run" command that will:

* Start a new container using "topics-mine" service's image and environment variables;
* Make the container join "mediacloud" Docker stack;
* Run "bash" in said container:
    
 docker run -it --network mediacloud_default -e MC_DOWNLOADS_STORAGE_LOCATIONS=amazon_s3 -e MC_DOWNLOADS_READ_ALL_FROM_S3=1 -e MC_DOWNLOADS_FALLBACK_POSTGRESQL_TO_S3=1 -e MC_DOWNLOADS_CACHE_S3=0 -e MC_DOWNLOADS_AMAZON_S3_ACCESS_KEY_ID=<...> -e MC_DOWNLOADS_AMAZON_S3_SECRET_ACCESS_KEY=<...> -e MC_DOWNLOADS_AMAZON_S3_BUCKET_NAME=<...> -e MC_DOWNLOADS_AMAZON_S3_DIRECTORY_NAME=<...> -e MC_EMAIL_FROM_ADDRESS=<...> -e MC_USERAGENT_BLACKLIST_URL_PATTERN=<...> -e MC_USERAGENT_AUTHENTICATED_DOMAINS=<...> -e MC_USERAGENT_PARALLEL_GET_NUM_PARALLEL=<...> -e MC_USERAGENT_PARALLEL_GET_TIMEOUT=30 -e MC_USERAGENT_PARALLEL_GET_PER_DOMAIN_TIMEOUT=1 -e MC_TOPICS_BASE_TOPIC_ALERT_EMAILS=<...> -e MC_TWITTER_CONSUMER_KEY=<...> -e MC_TWITTER_CONSUMER_SECRET=<...> -e MC_TWITTER_ACCESS_TOKEN=<...> -e MC_TWITTER_ACCESS_TOKEN_SECRET=<...> gcr.io/mcback/topics-mine:release bash

Make sure to:

* Preserve a single whitespace in front of the command so that the command doesn't get logged in shell history;
* Verify that you're starting a container using a correct image tag, e.g. "release".  

```

You can then copy a `docker run` command generated on your local development computer to a chosen production server and run it to start a new `topics-mine` container together with the configuration environment variables and the production network.
