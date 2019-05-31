#!/usr/bin/env python3

import os
from typing import List

from utils import (
    DockerHubConfiguration,
    container_dir_name_from_image_name,
    docker_images,
    current_git_branch_name,
    DockerHubArgumentParser,
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


def _docker_images_to_build(all_apps_dir: str, conf: DockerHubConfiguration) -> List[DockerImageToBuild]:
    """
    Return an ordered list of Docker images to build.

    :param all_apps_dir: Directory with app subdirectories.
    :param conf: Docker Hub configuration object.
    :return: List of Docker images to build in that order.
    """

    images_to_build = []

    for dependency in docker_images(all_apps_dir=all_apps_dir, only_belonging_to_user=True, conf=conf):
        container_name = container_dir_name_from_image_name(image_name=dependency, conf=conf)
        container_path = os.path.join(all_apps_dir, container_name)

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

    parser = DockerHubArgumentParser(description='Print commands to build all container images.')
    args = parser.parse_arguments()
    conf_ = args.docker_hub_configuration()

    branch = current_git_branch_name()

    for image in _docker_images_to_build(all_apps_dir=args.all_apps_dir(), conf=conf_):
        print('docker build --cache-from {image_name}:latest --tag {image_name}:{branch} --tag {image_name}:latest {container_path}'.format(
            branch=branch,
            image_name=image.tag,
            container_path=image.path,
        ))
