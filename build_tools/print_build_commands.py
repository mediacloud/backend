#!/usr/bin/env python3

import os
from typing import List

from utils import (
    DockerHubConfiguration,
    container_dir_name_from_image_name,
    argument_parser,
    docker_hub_configuration_from_arguments,
    docker_images,
)


class DockerImageToBuild(object):
    """
    A single container image to build.
    """

    __slots__ = [
        'name',
        'path',
        'tag',
    ]

    def __init__(self, name: str, path: str, tag: str):
        """
        Constructor.

        :param name: Container name.
        :param path: Container directory to build the image from.
        :param tag: Tag to add to the built image.
        """
        self.name = name
        self.path = path
        self.tag = tag


def _docker_images_to_build(all_containers_dir: str, conf: DockerHubConfiguration) -> List[DockerImageToBuild]:
    """
    Return an ordered list of Docker images to build.

    :param all_containers_dir: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: List of Docker images to build in that order.
    """

    images_to_build = []

    for dependency in docker_images(all_containers_dir=all_containers_dir, only_belonging_to_user=True, conf=conf):
        container_name = container_dir_name_from_image_name(image_name=dependency, conf=conf)
        container_path = os.path.join(all_containers_dir, container_name)

        if not os.path.isdir(container_path):
            raise ValueError("Container path is not a directory: '{}'".format(container_path))

        images_to_build.append(
            DockerImageToBuild(
                name=container_name,
                path=container_path,
                tag=dependency,
            )
        )

    return images_to_build


if __name__ == '__main__':

    parser = argument_parser(description='Print commands to build all container images.')
    args = parser.parse_args()
    conf_ = docker_hub_configuration_from_arguments(args)

    for image in _docker_images_to_build(all_containers_dir=args.all_containers_dir, conf=conf_):
        print(
            (
                'docker build --cache-from {image_name} --tag {image_name} {container_path}'

                # If initial 'docker build' fails, try building again without --cache-from because:
                #
                # * the image to be used for cache might not get pulled due to, say, network problems;
                # * the image might not exist at all if this is a new container image not built before
                #
                ' || '
                'docker build --tag {image_name} {container_path}'

            ).format(
                image_name=image.tag,
                container_path=image.path,
            )
        )
