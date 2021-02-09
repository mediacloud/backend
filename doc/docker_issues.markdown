<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [Common issues with Docker](#common-issues-with-docker)
      * [apt-get no longer works, it tells me to "maybe run apt-get update"](#apt-get-no-longer-works-it-tells-me-to-maybe-run-apt-get-update)
      * [I've started run.py &lt;app-name&gt; bash, ran a test, and it worked the first time but now it throws <code>McUniqueConstraintException</code> or something like that](#ive-started-runpy-app-name-bash-ran-a-test-and-it-worked-the-first-time-but-now-it-throws-mcuniqueconstraintexception-or-something-like-that)
      * [I'm out of disk space!](#im-out-of-disk-space)
      * [Container DNS seems to be able to resolve container hostnames but not external hosts](#container-dns-seems-to-be-able-to-resolve-container-hostnames-but-not-external-hosts)
      * [I've encounter funky inter-node communication problems in a swarm](#ive-encounter-funky-inter-node-communication-problems-in-a-swarm)

----
<!-- MEDIACLOUD-TOC-END -->


# Common issues with Docker

## `apt-get` no longer works, it tells me to "maybe run apt-get update"

All app container images derive from `base` container which loads an Ubuntu base image, runs `apt-get update`, installs a few utilities and does a bit of configuration (locale, timezone, email relay, etc.)

Given that `base` image doesn't change much, it doesn't get rebuilt too often and so APT's package listings fetched as a part of an initial build of `base` might get outdated as older versions of packages get removed from APTs repositories when new ones become available.

To make `apt-get` work again, either run `apt-get -y update` before installing a package, or update Ubuntu base image in `base`:

* *(Easiest to do but a temporary solution)* Run `apt-get -y update` before `apt-get -y install`:

  ```dockerfile
  RUN \
      # Update the package listing before attempting to install anything
      apt-get -y update && \
      # Install the package itself
      apt-get -y install my-package
  ```

  Updating the package listing right before installing a package is the quickest approach to remediate the problem, but due to how Docker layer caching works, this will lead to slower image builds and result in bigger images that get built.

  *or*

* *(Will hold for longer but everything will have to be rebuilt)* Update Ubuntu's base image's version in `base/Dockerfile`:

  ```diff
  --- apps/base/Dockerfile.old  2019-06-12 20:43:35.000000000 +0300
  +++ apps/base/Dockerfile  2019-06-12 20:43:50.000000000 +0300
  @@ -6,7 +6,7 @@
   #     docker build -t mediacloud-base .
   #
   
  -FROM ubuntu:focal-20200922
  +FROM ubuntu:focal-20201106
   
   ENV DEBIAN_FRONTEND noninteractive
   ENV LANG en_US.UTF-8
  ```

  There might be a new Ubuntu image published on [Ubuntu's repository on Docker Hub](https://hub.docker.com/_/ubuntu?tab=tags&page=1), so by updating `base` app's base Ubuntu image you'd trigger a full rebuild of every app in the repository, and by that you'd get a fresh APT package listing that you could use in your apps without having to run `apt-get -y update` before installing packages.

## I've started `run.py <app-name> bash`, ran a test, and it worked the first time but now it throws `McUniqueConstraintException` or something like that

Every Compose environment comes with a "clean slate" environment, i.e. empty Solr instance, PostgreSQL with only the initial schema preloaded, etc. Thus, every test assumes that it's running in such a clean slate environment, so it takes upon loading the fresh schema with some test data (if needed) and such. No test attempts to delete anything from PostgreSQL, Solr or any other database because 1) that's risky (what if we're running the test against a production database by accident?), and 2) it doesn't have to because every test gets run in a fresh isolated environment anyway.

When you a test for the first time in a freshly started Compose test environment (via `./dev/run.py <app-name> bash`), the test writes some test data into the database container(s), runs the actual test, and exits without attempting to do any kind of cleanup of any kind (as it safely assumes that the environment in which the test was run will be destroyed shortly anyway). When the same test or some other test gets run in the very same environment for the second time, the test tries to set up the database(s) with some test data once again, but at this point the environment in which the test is running is no longer "clean slate", so the setup stage of the test fails.

A remedy is to either restart the whole Compose test environment, or to run tests with `run_test.py` helper. Both approaches will clean up "dirty" containers after test gets finished, and subsequent runs will start brand new Compose environments for the test to use.

If you see this issue happening when running tests from an IDE (e.g. PyCharm), make sure that all (running and stopped) containers get removed before each test rerun, as per the PyCharm setup tutorial.

## I'm out of disk space!

Docker is not proactive about removing up old, stopped containers, deleting old, untagged, intermediate ("dangling") images, or cleaning up cache. Occasionally you have to do it yourself by running:

```bash
$ docker system prune
WARNING! This will remove:
        - all stopped containers
        - all networks not used by at least one container
        - all dangling images
        - all dangling build cache
Are you sure you want to continue? [y/N] y
<...>
Total reclaimed space: <...>
```

(You can skip the warning by running `docker system prune -f` instead.)

Given that cleaning up volumes is a bit more risky as they might contain some data that someone might want to preserve, `docker system prune` command doesn't remove unattached volumes. To do that, one has to run a separate command:

```bash
$ docker volume prune
WARNING! This will remove all local volumes not used by at least one container.
Are you sure you want to continue? [y/N] y
<...>
Total reclaimed space: <...>
```

(Similarly, you can add add `-f` flag to this command too to skip the warning.)

**Do not run `docker volume prune` on production!** Instead, opt for listing the volumes with `docker volume ls` and then removing them with `docker volume rm` individually.

## Container DNS seems to be able to resolve container hostnames but not external hosts

By default, Docker Compose's internal network uses 10.0.0.0/24 subnet, meaning that containers get assigned IPs between 10.0.0.0 and 10.0.0.255. If your host machine(s) use the same or overlapping subnet to communicate between host machines, you might encounter problems, e.g. if the host machine's DNS server is available on the same subnet (as is the case on EC2 instances), Docker's own embedded DNS might not be able to forward DNS queries for external hosts to the DNS service on your host network (as there might exist a container within Docker's overlap network that has the very same IP address).

To remediate that, either:

1. Use a different private subnet in your host network, or

2. Use a different private subnet in the overlay network created by Docker Compose by setting `ipam/config/subnet` in production `docker-compose.yml` file's `networks` section, e.g.:

    ```yaml
    networks:

        default:

            ipam:
              config:
                  # or "192.168.0.0/16", or something else altogether; just
                  # make sure that the subnet will be able to "fit" enough IP
                  # addresses for all of your containers (services and their
                  # replicas)
                  - subnet: "172.16.0.0/12"
    ```

## I've encounter funky inter-node communication problems in a swarm

If you encounter weird connectivity problems between nodes in a Docker Swarm, e.g. containers seem to be are able to connect to some containers but not the others, make sure that you've opened the required TCP and UDP ports between nodes as per deployment instructions.

