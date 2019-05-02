#!/usr/bin/env python3

from typing import List

from utils import DockerHubConfiguration, docker_images, DockerHubArgumentParser


def _docker_images_to_pull(all_containers_dir: str, conf: DockerHubConfiguration) -> List[str]:
    """
    Return an ordered list of Docker images to pull.

    :param all_containers_dir: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: List of tagged Docker images to pull in that order.
    """
    return docker_images(all_containers_dir=all_containers_dir, only_belonging_to_user=False, conf=conf)


if __name__ == '__main__':

    parser = DockerHubArgumentParser(description='Print commands to pull all container images.')
    args = parser.parse_arguments()
    conf_ = args.docker_hub_configuration()

    for image in _docker_images_to_pull(all_containers_dir=args.all_containers_dir(), conf=conf_):
        print('docker pull {}'.format(image))
