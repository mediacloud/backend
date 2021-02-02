<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [Deploying](#deploying)
      * [Ports](#ports)
         * [Docker swarm](#docker-swarm)
         * [Webapp](#webapp)
      * [ZFS pool](#zfs-pool)
      * [ZFS filesystems](#zfs-filesystems)
      * [Provisioning](#provisioning)
      * [Configuration](#configuration)
      * [Deploying](#deploying-1)
         * [SSH port forwarding](#ssh-port-forwarding)
         * [Deploying with Portainer](#deploying-with-portainer)
            * [Deploy Portainer itself](#deploy-portainer-itself)
            * [Deploy Media Cloud using Portainer](#deploy-media-cloud-using-portainer)
            * [Portainer's tips and gochas](#portainers-tips-and-gochas)
         * [Deploying manually](#deploying-manually)

----
<!-- MEDIACLOUD-TOC-END -->


# Deploying

To deploy your code changes, generally you would:

1. Merge changes into `release` Git branch and `git push` the branch;
2. Wait for the [continuous integration system](https://github.com/mediacloud/backend/actions) to pull images, rebuild the ones that have changed, and push the updated images to container repository;
3. Using either Portainer or Docker CLI, pull the updated images from the container repository and recreate app containers for which the images have been modified.

## Ports

### Docker swarm

Hosts that participate in the same Docker swarm should be able to connect **to each other** using the [following protocols and ports](https://docs.docker.com/engine/swarm/swarm-tutorial/#open-protocols-and-ports-between-the-hosts):

* TCP:
  * 2376
  * 2377
  * 7946
* UDP:
  * 4789
  * 7946
* ESP (IP protocol 50)

Sample UFW commands (assuming that `192.168.1.0/24` are Docker swarm nodes):

```bash
ufw allow from 192.168.1.0/24 to any port 2376 proto tcp comment "Media Cloud: Docker Swarm"
ufw allow from 192.168.1.0/24 to any port 2377 proto tcp comment "Media Cloud: Docker Swarm"
ufw allow from 192.168.1.0/24 to any port 7946 proto tcp comment "Media Cloud: Docker Swarm"
ufw allow from 192.168.1.0/24 to any port 4789 proto udp comment "Media Cloud: Docker Swarm"
ufw allow from 192.168.1.0/24 to any port 7946 proto udp comment "Media Cloud: Docker Swarm"
ufw allow from 192.168.1.0/24 to any proto esp comment "Media Cloud: Docker Swarm"
```

### Webapp

Host that exposes webapp to the public will have to have the following ports open:

* TCP:
  * 80
  * 443

## ZFS pool

We use ZFS filesystems for storing container data on the host system (which gets mounted to each container as a bind mount):

```bash
sudo apt install -y zfsutils-linux

# SAMPLE DEPLOYMENTS ONLY: create an empty file to serve as a backing disk for a pool
sudo dd if=/dev/zero of=/zfspool bs=1G count=10
sudo chown root:root /zfspool
sudo chmod 600 /zfspool

# Create a single "space" ZFS pool for all data
# (replace /zfspool with a path to your disk device)
sudo zpool create space /zfspool

# Create "space/mediacloud" ZFS filesystem for Media Cloud data
sudo zfs create space/mediacloud

# Enable compression and optimize the filesystem (and its descendants)
sudo zfs set compression=lz4 space/mediacloud
sudo zfs set recordsize=16K space/mediacloud
sudo zfs set primarycache=metadata space/mediacloud
sudo zfs set atime=off space/mediacloud
```

## ZFS filesystems

All container volumes get their own ZFS filesystem on the respective systems on which the containers are going to be run.

For example, to run PostgreSQL on `mcdb1`, all 24 Solr shards on `mcquery[1-3]` (8 shards on each server), and the rest on `mccore1`, create ZFS filesystems for volumes as follows:

```bash
# mccore1
sudo zfs create space/mediacloud/vol_rabbitmq_data
sudo zfs create space/mediacloud/vol_opendkim_config
sudo zfs create space/mediacloud/vol_postfix_data
sudo zfs create space/mediacloud/vol_daily_rss_dumps
sudo zfs create space/mediacloud/vol_munin_data
sudo zfs create space/mediacloud/vol_munin_html
sudo zfs create space/mediacloud/vol_portainer_data
sudo zfs create space/mediacloud/vol_pgadmin_data

# mcdb1
sudo zfs create space/mediacloud/vol_postgresql_data

# mcquery1
for shard_num in $(seq 1 8); do
    shard_num=$(printf "%02d" $shard_num)
    sudo zfs create "space/mediacloud/vol_solr_shard_data_${shard_num}"
done

# mcquery2
for shard_num in $(seq 9 16); do
    shard_num=$(printf "%02d" $shard_num)
    sudo zfs create "space/mediacloud/vol_solr_shard_data_${shard_num}"
done

# mcquery3
for shard_num in $(seq 17 24); do
    shard_num=$(printf "%02d" $shard_num)
    sudo zfs create "space/mediacloud/vol_solr_shard_data_${shard_num}"
done
```

## Provisioning

To install Docker and Docker Compose on multiple servers, join them in a swarm, and assign labels (to be used for placement constraints) to swarm's nodes, you can provision servers using an Ansible playbook available under `provision/`.

To provision multiple servers with Ansible:

1. In the `provision/inventory/` directory, copy `hosts.sample.yml` to `hosts.yml` and:
    * Add hostnames of servers that will make up a swarm.
    * Configure how to connect to every server (`ansible_user`, `ansible_ssh_private_key_file`, ...)
    * Set `docker_swarm_advertise_ip_or_if` to either the IP of which will be used to advertise the host (node) to the rest of the swarm, or the ethernet interface the IP of which should be read. Ideally, this should be an ethernet interface that connects the host to a private network between servers.
    * Define labels for every node (`docker_swarm_node_labels`) that will be used by production `docker-compose.yml` to determine which server should be used to run particular services (ones that use / share a volume or `mmap()`ped RAM).
    * Elect three swarm managers among the servers (`docker_swarm_managers`) and add the rest as workers (`docker_swarm_workers`).
2. In the `provision/` directory, run:

    ```bash
    ansible-playbook -vvv setup.yml
    ```

    to provision the hosts.

## Configuration

Production's `docker-compose.yml` defines what services are started, how they are to be configured, and where they should store their data (if any).

In the file, you might want to set the following:

* Common configuration variables (`x-common-configuration` section) that define global environment variables for apps derived from `common` base image.
* Per-service configuration environment variables (`environment:` section of every service) that configure containers of every service
* Replica counts (`deploy:replicas:` section) that set how many containers will every service start
* Resource limits (`deploy:resources:limits:` section) that define the upper limit of resources (CPU, RAM) that every container might use
* Named volumes list (`volumes:` section at the bottom at the file) that configure volume bindings to locations on the host computer

Template for production's `docker-compose.yml` file is available in `apps/docker-compose.yml`.

## Deploying

### SSH port forwarding

Both Media Cloud production's `docker-compose.yml` and Portainer's `docker-compose.portainer.yml` are configured to expose ports of certain apps to every node. Those ports are (to be) firewalled off from public access, but it might be useful to be able to access those services internally for debugging purposes. The services with published ports include (but might not be limited to):

* Solr's webapp on port 8983
* Munin's webapp on port 4948
* RabbitMQ's webapp on port 15672:
    * username: `mediacloud`
    * password: `mediacloud`
* Portainer's webapp on port 9000
    * username: `admin`
    * password: `mediacloud`
* pgAdmin on port 5050:
    * username: `mediacloud@mediacloud.org`
    * password: `mediacloud`

To access those services, you might want to set up a SSH tunnel in your `~/.ssh/config` as follows:

```
Host mccore1
    HostName <...>
    User <...>
    IdentityFile <...>

    # solr-shard-01
    LocalForward 8983 127.0.0.1:8983

    # munin-httpd
    LocalForward 4948 127.0.0.1:4948

    # rabbitmq-server
    LocalForward 15672 127.0.0.1:15672

    # portainer
    LocalForward 9000 127.0.0.1:9000

    # postgresql-pgadmin
    LocalForward 5050 127.0.0.1:5050
```

### Deploying with Portainer

#### Deploy Portainer itself

To be able to manage applications running on Docker Swarm using Portainer's web UI, you have to deploy Portainer itself.

To deploy Portainer:

1. Copy `apps/docker-compose.portainer.yml` to one of the swarm managers.

2. Deploy the Portainer's stack in the swarm:

   ```bash
   docker stack deploy -c docker-compose.portainer.yml portainer
   ```

3. Assuming that you have SSH port forwarding set up as per example below, you should be able to connect to Portainer's web UI by opening the following URL:

   <http://localhost:9000/>

   and logging in with the following credentials:

   * username: `admin`
   * password: `mediacloud`

#### Deploy Media Cloud using Portainer

To deploy Media Cloud services using Portainer's web UI:

1. Go to Portainer's web UI, select the `primary` endpoint, open a list of *Stacks* in the menu on the left, and click on *Add stack*;
2. Name the stack `mediacloud`, and either:
   * paste the contents of production's `docker-compose.yml` in the *Web editor* section, or
   * upload the prepared `docker-compose.yml` from your computer in the *Upload* section, or
   * make Portainer read production's `docker-compose.yml` from a private, authenticated Git repository in the *Repository* section;
3. Don't set any *Environment variables*, it is expected that the production's `docker-compose.yml` will have everything explicitly set in the file itself;
4. Click *Deploy the stack* and wait for the stack to deploy.

#### Portainer's tips and gochas

* To update a running stack with a newer production `docker-compose.yml`, open the *Editor* tab in the `mediacloud` stack page, update the Compose configuration, and click *Update the stack*;
* Feel free to use Portainer's features to scale the services, update their configuration via environment variables, update resource limits, etc., using the web UI, just make sure to reflect the changes that you've made in the private authenticated Git repository with production `docker-compose.yml`.
* Sometimes, after navigating your browser to the previous page with a list of containers, Portainer might show one or more duplicate containers for a non-replicated service, e.g.:

    ![](https://github.com/mediacloud/backend-docs-images/raw/master/portainer/duplicate-containers.png)

    This seems to be Portainer's bug. To see a correct number of service containers, click on the *Refresh* button at the top of the page (browser's page reload might not always work).

### Deploying manually

To deploy services, change the current directory to the one with production's `docker-compose.yml` and then run:

```bash
docker stack deploy -c docker-compose.yml mediacloud
```

To update services (e.g. after updating configuration in `docker-compose.yml` or pushing new container images), run the same command again.

To stop all services by stopping and removing all the containers, run:

```bash
docker stack rm mediacloud
```

Despite the name, the command `docker stack rm` is not destructive as it stops and removes the containers only and leaves the volumes with data untouched.

