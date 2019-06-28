# Deploying

To deploy your code changes, generally you would:

1. Merge changes into `release` Git branch and `git push` the branch;
2. Wait for the [continuous integration system](https://dev.azure.com/shirshegsm/mediacloud/_build) to pull images, rebuild the ones that have changed, and push the updated images to [Docker Hub](https://hub.docker.com/u/dockermediacloud) repository;
3. Using either Portainer or Docker CLI, pull the updated images from the Docker Hub repository and recreate app containers for which the images have been modified.

## Ports

### Docker swarm

Hosts that participate in the same Docker swarm should be able to connect **to each other** using the [following protocols and ports](https://docs.docker.com/engine/swarm/swarm-tutorial/#open-protocols-and-ports-between-the-hosts):

* TCP:
  * 2376
  * 2377
  * 7946
* UDP:
  * 7946
  * 4789
* ESP (IP protocol 50)

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
sudo zfs create space/mediacloud/vol_postfix_local_mail
sudo zfs create space/mediacloud/vol_postfix_queue
sudo zfs create space/mediacloud/vol_daily_rss_dumps
sudo zfs create space/mediacloud/vol_munin_data
sudo zfs create space/mediacloud/vol_munin_html
sudo zfs create space/mediacloud/vol_proxy_ssl_certs
sudo zfs create space/mediacloud/vol_portainer_data

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
    * Set the name of the ethernet interface the IP of which will be used to advertise the host (node) to the rest of the swarm (`docker_swarm_advertise_interface`). Ideally, this should be an ethernet interface that connects the host to a private network between servers.
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

### `common` configuration



## Deploying

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

