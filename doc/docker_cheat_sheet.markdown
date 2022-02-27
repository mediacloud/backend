<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [Cheat sheet](#cheat-sheet)
      * [Refer container by ID](#refer-container-by-id)
      * [SSH into a container](#ssh-into-a-container)
      * [Run psql](#run-psql)

----
<!-- MEDIACLOUD-TOC-END -->


# Cheat sheet

## Refer container by ID

To avoid excessive typing or copy-pasting when running Docker commands, you can refer to a container by only a part of its ID:

```bash
# PostgreSQL container has an ID "72bfc559a72b"
$ docker ps -a
CONTAINER ID        IMAGE                                       COMMAND
72bfc559a72b        gcr.io/mcback/postgresql-server:latest   "/opt/mediacloud/bin…"

# ...but we can refer to it using only a part of the ID ("72b")
$ docker inspect 72b
[
    {
        "Id": "72bfc559a72b88a88262c3717e4406e36b4d86730bf22f2dcbba5046edd473f2",
        "Created": "2019-06-12T16:47:15.1030581Z",
        # ...
    }
]
```

## SSH into a container

Given that behind the scenes a container is just a fancy chroot, it wouldn't make much sense to SSH into it because that would amount to you SSHing into your own machine. Instead, you can use one of the following commands:

* To run `bash` in a **running** container:

  1. Find out running container's ID:

     ```bash
     $ docker ps
     CONTAINER ID        IMAGE                           COMMAND
     <...>
     b519dab9d10b        gcr.io/mcback/<...>:latest   "important_research.sh"
     ```

  2. Run `docker exec -it <container_id_or_just_a_part_of_it> bash`:

     ```bash
     $ docker exec -it b5 bash
     mediacloud@b519dab9d10b:/$
     ```

     Docker will start an interactive `bash` session in addition to container's main command (`important_research.sh` in this case).

* To **start a new container** and **run `bash`** instead of image's default command:

  1. Run `docker run -it --entrypoint=bash <image_name>`:

     ```bash
     $ docker run -it --entrypoint=bash gcr.io/mcback/tools:latest
     mediacloud@f5a121fe5907:/$ 
     ```

* To run `bash` in a **stopped** container, either:

  1. `docker start` it first and then run `docker exec` as detailed above, or
  2. Export the stopped container to an image with `docker commit` and then start a new container from said image as [detailed here](https://stackoverflow.com/a/39329138)

## Run `psql`

To access PostgreSQL directly, you can either run `psql` in a `postgresql-server` container, or map the port from a PostgreSQL container to your host machine and access it from there. At present, Media Cloud
runs our PostgreSQL server [on `woodward`](https://github.com/mediacloud/production-docker-config/blob/master/hosts.yml#L69-L70); you can also access PostgreSQL data by `ssh`ing to `bd-postgresql.srv.mediacloud.org`.

* To run **`psql` in PostgreSQL container**:

  1. Find out container ID of a running PostgreSQL's container:

     ```bash
     $ docker ps | grep postgres
     CONTAINER ID        IMAGE                                       COMMAND
     29ad7542c5fe        gcr.io/mcback/postgresql-server:latest   "/opt/mediacloud/bin…"
     ```

  2. Execute `psql` in a running PostgreSQL container:

     ```bash
     $ docker exec -it 29a psql
     psql (13.3 (Ubuntu 11.3-1.pgdg20.04+1))
     Type "help" for help.
     
     mediacloud=# 
     ```

* To run **`psql` on your host machine**:

  1. Make sure that nothing is listening on the host machine's port to which you're about to bind the container's port;

  2. Add a port mapping *before* you start a new PostgreSQL container:

     * If you're running a standalone PostgreSQL container, add a port mapping by adding `-p [host_bind_ip:]host_port:container_port` argument to `docker run`:

       ```bash
       $ docker run -d -p "127.0.0.1:5432:5432" gcr.io/mcback/postgresql-server:latest
       ```

     * If you're running PostgreSQL container as part of a (testing) Docker Compose environment, add a port mapping by defining `ports:` directive to `docker-compose.tests.yml`:

       ```yaml
       version: "3.7"
       
       services:
       
          # <...>
          
           postgresql-server:
               image: gcr.io/mcback/postgresql-server:latest
               # <...>
               ports:
                   # "[host_bind_ip:]host_port:container_port"
                   - "127.0.0.1:5432:5432"
       ```

       and then start the whole Compose environment with `-m` (`--map_ports`) argument to `run.py`:

       ```bash
       $ ./dev/run.py -m common bash
       ```

  3. After starting either a standalone PostgreSQL container or a Compose environment with PostgreSQL as one of the services in it, container's port should be mapped to the host machine as defined either in `-p` argument to `docker run` or `ports:` section in `docker-compose.tests.yml`:

     ```bash
     $ docker ps | grep postg
     CONTAINER ID        IMAGE                                       PORTS
     72bfc559a72b        gcr.io/mcback/postgresql-server:latest   127.0.0.1:5432->5432/tcp
     ```

     and you should be able to connect to the container from your host machine as you would with any other PostgreSQL instance:

     ```bash
     $ psql -h localhost -U mediacloud -d mediacloud
     Password for user mediacloud: 
     Timing is on.
     Expanded display is on.
     psql (13.3)
     Type "help" for help.
     
     mediacloud=# 
     ```

* To **dump PostgreSQL tables to your host machine**:

   1. `ssh` to the server running PostgreSQL and find its container ID, as described above.
   
   2. Choose the table you want and dump it as a `.sql` file with the following syntax:

      ```docker exec 123somecontainer456 pg_dump --table=media > media.sql`

      Note that there are certain tables (e.g. `story_sentences`) that are so large as to be infeasible
      to work with locally. You can check that by running `du` on the dumped `.sql` file while `ssh`ed
      into the server, e.g. `du media.sql --block-size=1MB`.

   3. Copy the `.sql` file to a directory on your host machine via `scp`, e.g.

      ```scp james@bd-postgresql.srv.mediacloud.org:/nfs/home/james/media.sql ./```

   4. Load the `.sql` file to the local database of your choice. For example, if you want to use
      PostgreSQL, create a database, connect to it via `psql` and load the table with a
      command along the lines of 
      
      ```mediacloud=# \i '/home/james/mediacloud/sql_dumps/media.sql'```
