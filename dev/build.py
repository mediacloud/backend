#!/usr/bin/env python3

"""
(Re-)build Docker images for all apps, and tag them with both the name of the current Git branch and "latest".

Usage:

    ./dev/build.py

This script can print the commands that are going to be run instead of running them itself:

    # "bash -e" because we want to stop on the first error
    ./dev/build.py -p | grep solr-shard | bash -e

Make sure to run pull.py before rebuilding any images to increase the layer cache reuse.

"""

import os
import subprocess
from typing import List

from utils import (
    container_dir_name_from_image_name,
    docker_images,
    docker_tag_from_current_git_branch_name,
    CRPruneArgumentParser,
)


class DockerImageToBuild(object):
    """
    A single container image to build.
    """

    __slots__ = [
        'name',
        'path',
        'repository',
    ]

    def __init__(self, name: str, path: str, repository: str):
        """
        Constructor.

        :param name: Container name, e.g. "common".
        :param path: Container directory to build the image from, e.g. "../apps/topics-mine-public/".
        :param repository: Repository name add to the built image, e.g. "mc2021/common".
        """
        self.name = name
        self.path = path
        self.repository = repository


def _docker_images_to_build(all_apps_dir: str) -> List[DockerImageToBuild]:
    """
    Return an ordered list of Docker images to build.

    :param all_apps_dir: Directory with app subdirectories.
    :return: List of Docker images to build in that order.
    """

    images_to_build = []

    for dependency in docker_images(all_apps_dir=all_apps_dir, only_belonging_to_user=True):
        container_name = container_dir_name_from_image_name(image_name=dependency)
        container_path = os.path.join(all_apps_dir, container_name)

        if not os.path.isdir(container_path):
            raise ValueError("Container path is not a directory: '{}'".format(container_path))

        images_to_build.append(
            DockerImageToBuild(
                name=container_name,
                path=container_path,
                repository=dependency,
            )
        )

    return images_to_build


if __name__ == '__main__':

    parser = CRPruneArgumentParser(description='Print commands to build all container images.')
    args = parser.parse_arguments()

    image_tag = docker_tag_from_current_git_branch_name()

    images = _docker_images_to_build(all_apps_dir=args.all_apps_dir())

    for image in images:
        command = "docker build --cache-from {repo}:latest --tag {repo}:{tag} --tag {repo}:latest {path}".format(
            repo=image.repository,
            tag=image_tag,
            path=image.path,
        )

        if args.prune_images():
            command += ' && docker image prune -f'

        if args.print_commands():
            print(command)
        else:
            # Run build commands, stop at the first failed build
            subprocess.check_call(command, shell=True)
