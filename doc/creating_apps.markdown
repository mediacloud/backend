# Creating apps

Every app gets built to a Docker container image which then gets named with the app's name, e.g. `solr-zookeeper` app gets built to `dockermediacloud/solr-zookeeper` image to be later used for running the ZooKeeper from within the Docker Compose environment.

## App names can't have underscores (`_`) in them

```bash
# BAD! App name contains an underscore.
$ ls -l apps/
<...>
drwxr-xr-x@  9 pypt  staff    288 Jun  7 21:30 postgresql_server
```

Image's base name will later become container's name, containers use their names as one of the hostnames that they "identify" as (i.e. if you're running `solr-zookeeper` container in a Docker Compose network, you can access it from some container using the `solr-zookeeper` hostname), and [hostnames can't have underscores in their names](https://en.wikipedia.org/wiki/Hostname#Restrictions_on_valid_host_names).

So, instead of an underscore, always use hyphens (`-`) in app, image and container names:

```bash
# Good! App name doesn't contain an underscore.
$ ls -l apps/
<...>
drwxr-xr-x@  9 pypt  staff    288 Jun  7 21:30 postgresql-server
```

## Tag versions

Every image will have one or more tags assigned to it. Tag names are mapped to Git repository branch names.

```bash
$ docker images | grep solr
REPOSITORY                       TAG         IMAGE ID      CREATED     SIZE
<...>
dockermediacloud/solr-zookeeper  containers  70690b3b9616  5 days ago  829MB
dockermediacloud/solr-zookeeper  latest      70690b3b9616  5 days ago  829MB
dockermediacloud/solr-shard      containers  c6fe1da28bb7  6 days ago  764MB
dockermediacloud/solr-shard      latest      c6fe1da28bb7  6 days ago  764MB
dockermediacloud/solr-base       containers  9185076145e3  6 days ago  704MB
dockermediacloud/solr-base       latest      9185076145e3  6 days ago  704MB
```

 A single exception is the tag **`latest`** which has a special meaning - it always refers to the ***last pulled or built image from any branch**. Due to the ambiguous nature of the `latest` tag, **images tagged as `latest` are never to be pushed to the [Docker Hub repository](https://hub.docker.com/r/dockermediacloud/solr-shard/tags)** - `latest` is only to be used internally, for running code against development builds.

As specified in the Docker Compose configuration template for production (`apps/docker-compose.yml.dist`), production environments always run images tagged with `release`, thus built from the `release` Git branch.

## App layout in container image

Most applications that derive from `common` base image use the following layout for their source code in the container image:

* `/opt/mediacloud/` - base directory for source code, entry point scripts, tests and test data (both mounted as volumes from host computer);
  * `/opt/mediacloud/bin/` - directory for storing app's "entry point" scripts, i.e. scripts that start the app itself (e.g. Celery worker's main script), or run an auxiliary task using the app's source code (e.g. web app's user management script in `webapp-api` app); directory gets added to `PATH` in `common` base image's `Dockerfile`;
  * `/opt/mediacloud/src/` - directory with Perl / Python source code;
    * `/opt/mediacloud/src/<app-name>/` - directory with Perl / Python source code of app `<app-name>`;
      * `/opt/mediacloud/src/<app-name>/perl/` - directory with Perl source of app `<app-name>`; directory gets added to `PERL5LIB` in app's own `Dockerfile`;
      * `/opt/mediacloud/src/<app-name>/python/` - directory with Python source of app `<app-name>`; directory gets added to `PYTHONPATH` in app's own `Dockerfile`;
  * `/opt/mediacloud/tests/` - Perl / Python tests of the app; *not* baked at build time but instead mounted as a volume in every app's `docker-compose.tests.yml`;
    * `/opt/mediacloud/tests/perl/` - Perl tests of the app;
    * `/opt/mediacloud/tests/python/` - Python tests of the app.

Even though the layout of the app's container image is up to the app, various developer scripts (e.g. `run_test.py` or `run_all_tests.py`) will expect to find tests in `/opt/mediacloud/tests/`, so it is recommended to at least loosely follow the structure above.

Every app that copies its own Perl / Python source code to the image in `Dockerfile` has to prepend location of said source code to `PERL5LIB` and `PYTHONPATH`:

```dockerfile
# Copy sources of "topics-fetch-link" app
COPY src/ /opt/mediacloud/src/topics-fetch-link/
ENV PERL5LIB="/opt/mediacloud/src/topics-fetch-link/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/topics-fetch-link/python:${PYTHONPATH}"
```

Nested app images then can use source code of their own plus of the parent images without having to modify the library search paths in any way. For example, `topics-fetch-link` app uses `topics-base` as its base image which, in turn, uses `common` as its base image. Given that all three of these images modified Perl / Python library search paths at build time, the final library search paths then become configured to find Perl / Python libraries in both the app's own source code directory and directories of parent images:

```bash
# Library search paths of "topics-fetch-link" app
$ docker run --entrypoint env dockermediacloud/topics-fetch-link:latest | grep -E 'PERL5LIB|PYTHONPATH'
PERL5LIB=/opt/mediacloud/src/topics-fetch-link/perl:/opt/mediacloud/src/topics-base/perl:/opt/mediacloud/src/common/perl
PYTHONPATH=/opt/mediacloud/src/topics-fetch-link/python:/opt/mediacloud/src/topics-base/python:/opt/mediacloud/src/common/python
```

## Writing `Dockerfile`s

In addition to the official [best practices for writing `Dockerfile`s](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#leverage-build-cache), consider using the tips below as well.

### Run app's main script using unprivileged user

```dockerfile
# BAD! Script gets run as "root", which is container's own "root" so it's not quite the same as host
# computer's "root" but is still insecure as the container's "root" can leak into host's "root" due
# to a vulnerability
CMD ["topics_fetch_link_worker.py"]
```

```dockerfile
# Good! At build time, set the user to "mediacloud" (created in "common") or some other unprivileged
# user ("nobody", "www-data", ...) right before you set the image's CMD so that the command gets
# executed using that unprivileged user
USER mediacloud

CMD ["topics_fetch_link_worker.py"]
```

### Do "heavy" operations first, "volatile" operations last

When building a `Dockerfile`, Docker tries to [use pre-built images as cache to be able to skip rebuilding layers](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#leverage-build-cache).

```dockerfile
# BAD! With every change of the app's source code, the build process will have to copy the
# source code first and then reinstall the superheavy dependency every time

COPY src/ /opt/mediacloud/src/

RUN apt-get -y install super-heavy-dependency
```

Instead, try to optimize the `Dockerfile` so that the more heavy operations (e.g. downloading huge files, precomputing resources) get run first, and more volatile steps (e.g. copying app's source code) end up after the heavy operations.

```dockerfile
# Good! Install the superheavy dependency first so that it doesn't have to be reinstalled on
# every rebuild (triggered by app's source code changes)

RUN apt-get -y install super-heavy-dependency

COPY src/ /opt/mediacloud/src/
```

### Print logs to STDOUT and STDERR

Make sure that all the logging of the app happens in STDOUT and STDERR because then the logs become accessible in Docker's own logging facility (`docker logs`) and are easier to track and archive.

To achieve that, you can:

* Configure the app log to STDOUT / STDERR directly, i.e. just print its log to the standard output;

* Configure the app to write logs to `/dev/stdout` and / or `/dev/stderr`, e.g.:

  ```
  # Write lighttpd's access log to /dev/stdout and error log to /dev/stderr
  accesslog.filename = "/dev/stdout"
  server.errorlog    = "/dev/stderr"
  ```

* Replace the log file with symlink(s) to `/dev/stdout` and / or `/dev/stderr` at build time, e.g.:

  ```dockerfile
  # Set up Apache's logging to STDOUT / STDERR
  RUN \
      rm -f /var/log/apache2/access.log && \
      rm -f /var/log/apache2/error.log && \
      ln -s /dev/stdout /var/log/apache2/access.log && \
      ln -s /dev/stderr /var/log/apache2/error.log && \
      true
  ```

* In Cron jobs, pipe the job's STDOUT to `/dev/stdout` and STDERR to `/dev/stderr`, e.g.:

  ```
  # m h dom mon dow user    command
  
  14  5 *   *   *   root    /opt/mediacloud/bin/renew_le_certs.sh 1> /dev/stdout 2> /dev/stderr
  ```

* If the app insists on logging to syslog and can't be configured to log to a plain file, use `/rsyslog.inc.sh` helper in your wrapper script to start rsyslog before you start your app:

  ```bash
  #!/bin/bash
  
  set -e
  
  # Set up rsyslog for logging
  source /rsyslog.inc.sh
  
  # Start OpenDKIM
  exec opendkim
  ```

If you're running your app as an unprivileged user (and you should do so for many apps), the app might not have a permission to write to `/dev/stdout` and `/dev/stderr`, so you might have to `chmod` those locations before starting the main app in a wrapper script:

```bash
#!/bin/bash

set -e

# Make sure "munin" user is able to write to STDOUT / STDERR
chmod 666 /dev/stdout /dev/stderr

exec lighttpd -D -f /etc/lighttpd/lighttpd.conf
```

### Don't store anything important in container itself

As per Docker's "philosophy", containers should be treated as being ephemeral, meaning that **one shouldn't write app's data to the container's filesystem** or rely on a specific container not being removed. In a typical deployment cycle, old containers derived from outdated codebases get stopped and removed while new containers created from updated images take their place.

Simply put, if you want to retain data generated by a container, put in in a (named) volume.

### Run only a single thing per container

When possible, containers should be made to run a single thing (typically a process) per container only. This makes containers themselves easier to build, run, test and scale, a container-based system easier to maintain:

* Every process gets their own log exposed though Docker's logging facilities (`docker logs`);
* Containers (processes) can be scaled through Compose's replication (`deploy/replicas/`) so there's no need to reinvent scaling in the process itself (keeping track of children PIDs, autorestarting dead children, configuring number of forks / threads, etc.);
* Containers can have their resources limited by Compose (`deploy/resources/limits`) so a single process can be prevented from going rogue;
* Multiple containers can still run on the same host machine, potentially sharing a single disk resource (through the use of a single volume in all containers) or allocated memory (though `mmap()` or some other means);
* Simpler, lean containers are easier and quicker to build, e.g. a container that provides only FastCGI workers to a HTTP server doesn't have to depend on and install the HTTP server itself on every rebuild.

So, avoid making containers multi-purpose and multi-concern, e.g.:

* Don't run multi-process control systems, e.g. Supervisor, in containers; instead, implement your processes as separate containers and run them using a Compose configuration;
* When creating a web app, don't make the same container run both the HTTP server (e.g. Apache) and the FastCGI workers. Instead, create two separate containers for the HTTP server and a FastCGI worker, configure the HTTP server container to use FastCGI workers by connecting to them via TCP socket, put everything in a Compose configuration, and set the number of FastCGI worker replicas accordingly.

The rule of thumb here is that it's easier to build and maintain a couple of lean, single-concern containers and join them together into a single system using Compose than to have a single container which tries to do everything at once and exists just for the sake of having less containers (which by itself is not a useful goal to have).
