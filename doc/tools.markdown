<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [tools app](#tools-app)
      * [Run tool in background](#run-tool-in-background)
      * [Attach tool to existing network](#attach-tool-to-existing-network)
      * [What is and isn't a "tool"](#what-is-and-isnt-a-tool)

----
<!-- MEDIACLOUD-TOC-END -->


# `tools` app

`tools` app contains miscellaneous one-off tools that don't carry enough "weight" to become its own app. All the tools get copied to `/opt/mediacloud/bin/` which is in `PATH` so one can run a specific tool as follows:

```bash
# Run "fetch_url.pl" command in "tools" container
$ docker run -it dockermediacloud/tools:release fetch_url.pl
usage: /opt/mediacloud/bin/fetch_url.pl < url > at /opt/mediacloud/bin/fetch_url.pl line 16.
```

## Run tool in background

If a specific tool has to run for a prolonged period of time, you can run it in a "detached" mode (`-d` flag) and tail its logs:

```bash
# Start printing the date every second in a "detached" mode
$ docker run -d -it dockermediacloud/tools:release "while true; do date; sleep 1; done" 
b519dab9d10bdd715f592fd841a3a5b9f508e52b3a4c27207a9a258cb0a7f3b1

# Print the logs of the container and "follow" the log
$ docker logs -f b519dab9d10bdd715f592fd841a3a5b9f508e52b3a4c27207a9a258cb0a7f3b1
<...>
Tue Jun 11 08:33:01 EDT 2019
Tue Jun 11 08:33:02 EDT 2019
Tue Jun 11 08:33:03 EDT 2019
```

## Attach tool to existing network

If a tool is expected to access an existing Docker Compose environment (e.g. you want to run a tool against a production database), you can attach the tool container to said environment's network:

```bash
# (terminal 1) Create a sample network to attach to
$ ./dev/run.py common bash
<...>
Creating mc-common-bash_postgresql-pgbouncer_1 ... done
<...>
root@09a02bb9f178:/#
```

```bash
# (terminal 2) Find out the network name and run a tool attached to this network
$ docker network ls | grep common
cfeb15e2338f        mc-common-bash_default   bridge              local

# (terminal 2) Using the "tools" image, start a new container with "bash" set as command and attach
# it to the sample network that we've created in terminal 1
$ docker run --network mediacloud_default -it dockermediacloud/tools:release bash

# Container is now connected to the network and is able to access containers in it
mediacloud@24352eba1be1:/$ ping -c 1 postgresql-pgbouncer
PING postgresql-pgbouncer (172.18.0.6) 56(84) bytes of data.
64 bytes from mc-common-bash_postgresql-pgbouncer_1.mc-common-bash_default (172.18.0.6): icmp_seq=1 ttl=64 time=0.165 ms

--- postgresql-pgbouncer ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.165/0.165/0.165/0.000 ms
```

## Notes

### Tags

As detailed in [Creating apps](creating_apps.markdown) document, the `latest` tag denotes the latest *locally* built image (and is never pushed to the image repository), and the rest of the tags map to Git branches that they were built from, e.g. `release`.

So, when running a tool in production, you might want to use `dockermediacloud/tools` image tagged with `release` as it's the one that has been the latest "released" version of the `tools` repository:

```bash
#                                                                    vvvvvvv
$ docker run --network mediacloud_default -it dockermediacloud/tools:release bash
```

However, if you're running a tool in your local dev environment and would like to use the most recently pulled / built `tools`, you might want to go for `latest` (assuming that you've just pulled / built the `tools` image):

```bash
#                                                                        vvvvvv
$ docker run --network mc-common-bash_default -it dockermediacloud/tools:latest bash
```

### Network names

In production, Docker Swarm uses a network called `mediacloud_default`, so to be able to access the rest of the services (e.g. PostgreSQL or Solr) from your `tools` container, you might want to connect to that:

```bash
#                      vvvvvvvvvvvvvvvvvv
$ docker run --network mediacloud_default -it dockermediacloud/tools:release bash
```

However, if you're running a tool in your local dev environment and would like for it to attach to a testing Docker Compose environment started with `./dev/run.py`, you'll have to look up the network name first as it's different for every app and command that gets run in the app:

```bash
$ ./dev/run.py common bash
<...>
Creating network "mc-common-bash_default" with the default driver
<...>

$ docker network ls
NETWORK ID          NAME                     DRIVER              SCOPE
<...>
1d388b04968e        mc-common-bash_default   bridge              local

#                                                                        vvvvvv
$ docker run --network mc-common-bash_default -it dockermediacloud/tools:latest bash
```

## What is and isn't a "tool"

As mentioned before, `tools` app is limited to one-off scripts that do a certain thing against a Media Cloud deployment. `tools` app shouldn't be used for developing, building and running whole apps due to a perceived "easiness" of just having everything in a single container image.

Signs for when a tool should become its own app (with its own `Dockerfile`, source code, tests, deployment strategy etc.):

* **Tool has multiple Perl / Python module dependencies.** Adding one or two module dependencies to `tools` app's own `requirements.txt` / `cpanfile` in order to accommodate running one of the tools is fine, but if the number of dependencies keeps on growing, it would be tremendously easier if said tool was moved to its own app.
* **Tool has tests.** If testing needs to be done against a tool's source code, it's a good sign that a tool has became complex and important enough to deserve its own app.
* **Tool has to be started together with the rest of the apps in production's Compose environment.** It will be easier to configure, debug, monitor and manage the tool in a production environment if it gets its own app.
* **Other apps depend on the tool to be running.** If one or more of the apps depend on the tool to be actively running in a testing (`docker-compose.tests.yml`) or production environment, the tool should go into its own app to make it easier to configure other apps to start the tool in order to test it or use it for production needs.
* **Tool's code base is too big.** If you notice that a specific tool has grown to have a source code base of a considerable size, it is probably worth it to move it to its own app to make it more easily testable, separate out dependencies, and keep the `tools` app small in terms of size and complexity.
