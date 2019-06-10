#!/usr/bin/env python3

"""
(Re-)build Docker images for all apps, and tag them with both the name of the current Git branch and "latest".

Usage:

    ./dev/build.py

This script can print the commands that are going to be run instead of running them itself:

    ./dev/build.py -p | grep solr-shard | bash

Make sure to run pull.py before rebuilding any images to increase the layer cache reuse.

"""

import os
import subprocess
from typing import List

from utils import container_dir_name_from_image_name, docker_images, current_git_branch_name, DockerHubArgumentParser


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


def _docker_images_to_build(all_apps_dir: str, docker_hub_username: str) -> List[DockerImageToBuild]:
    """
    Return an ordered list of Docker images to build.

    :param all_apps_dir: Directory with app subdirectories.
    :param docker_hub_username: Docker Hub username.
    :return: List of Docker images to build in that order.
    """

    images_to_build = []

    for dependency in docker_images(
            all_apps_dir=all_apps_dir,
            only_belonging_to_user=True,
            docker_hub_username=docker_hub_username,
    ):
        container_name = container_dir_name_from_image_name(
            image_name=dependency,
            docker_hub_username=docker_hub_username,
        )
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
    docker_hub_username_ = args.docker_hub_username()

    branch = current_git_branch_name()

    images = _docker_images_to_build(all_apps_dir=args.all_apps_dir(), docker_hub_username=docker_hub_username_)

    for image in images:
        command = [
            'docker', 'build',
            '--cache-from', '{}:latest'.format(image.tag),
            '--tag', '{}:{}'.format(image.tag, branch),
            '--tag', '{}:latest'.format(image.tag),
            image.path,
        ]

        if args.print_commands():
            print(' '.join(command))
        else:
            subprocess.check_call(command)
