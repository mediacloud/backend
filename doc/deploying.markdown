# Deploying

To deploy your code changes, generally you would:

1. Merge changes into `release` Git branch and `git push` the branch;
2. Wait for the [continuous integration system](https://dev.azure.com/shirshegsm/mediacloud/_build) to pull images, rebuild the ones that have changed, and push the updated images to [Docker Hub](https://hub.docker.com/u/dockermediacloud) repository;
3. Using either Portainer or Docker CLI, pull the updated images from the Docker Hub repository and recreate app containers for which the images have been modified.

## Ports

Hosts that participate in the same Docker swarm should be able to connect to each other using the [following protocols and ports](https://docs.docker.com/engine/swarm/swarm-tutorial/#open-protocols-and-ports-between-the-hosts):

* TCP/2376
* TCP/2377
* TCP/7946
* UDP/7946
* UDP/4789
* ESP (IP protocol 50)
