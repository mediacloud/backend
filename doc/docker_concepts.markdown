# General Docker concepts

* **Docker** is our particular tool of choice of running multiple apps in their own isolated environments ("containers"). A good way to think of Docker is that by itself is not much more than a fancy [chroot](https://en.wikipedia.org/wiki/Chroot) with a few extra features (Linux kernel control groups for resource limits, and namespaces for process isolation); there even exists a [Docker implementation in 100 lines of Bash](https://github.com/p8952/bocker) that illustrates this point. Most of Docker ado and complexity comes from a certain "philosophy" bundled together with the Docker product that defines how those containers (which, again, are just a bunch of chroots with an additional cgroup and a namespace put on top of it) should be built and run.

* **Docker Compose** is a Python script that makes it easier to make a couple of Docker containers run together and talk to each other. Of course, [there's a bit more to it than that](https://docs.docker.com/compose/compose-file/), but that's the gist of it. Technically you can start a couple of Docker containers manually, add them to the same network and achieve the same effect, but Docker Compose (through its configuration `docker-compose.yml` in which you declare which containers you want to run and how) makes it easier to do that.

* **App**, in Media Cloud's own lingo, is something that we have to run in order to make the whole Media Cloud thing work. It might be some third-party software (e.g. PostgreSQL, Solr, or RabbitMQ), or something that we wrote ourselves (crawler, extractor, web API). Every app has:

  * Its own dependencies (e.g. APT packages or Perl/Python modules);
  * Its own source code within its own namespace;
  * Its own tests.

  Perhaps confusingly, some "apps" aren't really much of apps themselves because they serve as "base" other apps. For example, `common` app is a sort of Media Cloud's "standard library" with a lot of shared code (job broker, PostgreSQL database handler, HTTP client, Solr client, …) for other apps to use, but `common` doesn't do anything useful by itself.

* **Image** is what you get by building an app using its `Dockerfile`. An image is a read-only snapshot of a container's filesystem that will later be used to start a container in order to run a specific app. Images can be pushed to the remote image repository, pulled from it, or archived.

* **Container** is an instance of an image that's used for running the actual app encapsulated within an image. A container is not read-only and can be used to create new images (which are effectively snapshots of containers anyway). One can run multiple containers derived from the same image.

* **Volume** is typically a mount from a host machine to the container that is used for using and preserving container's data. Given that containers come and go as part of typical development and deployment cycles, they have to write and read their data (if any) from a volume that is mounted to a container.


## Links

* [Docker Compose file (`docker-compose.yml`) reference](https://docs.docker.com/compose/compose-file/)
* [`Dockerfile` reference](https://docs.docker.com/engine/reference/builder/)
* [Best practices for writing `Dockerfile`s](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
* [How to run Docker and get more sleep than I did](https://engineering.gusto.com/how-to-run-docker-and-get-more-sleep-than-i-did/)
