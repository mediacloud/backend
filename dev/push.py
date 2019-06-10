#!/usr/bin/env python3

"""
Push Docker images for all apps that are tagged with the name of the current Git branch.

Usage:

    ./dev/push.py

This script can print the commands that are going to be run instead of running them itself:

    ./dev/push.py -p | grep solr-shard | bash

"""

import subprocess
from typing import List

from utils import docker_images, current_git_branch_name, DockerHubArgumentParser


def _docker_images_to_push(all_apps_dir: str, docker_hub_username: str) -> List[str]:
    """
    Return an ordered list of Docker images to push.

    :param all_apps_dir: Directory with container subdirectories.
    :param docker_hub_username: Docker Hub username.
    :return: List of tagged Docker images to push in that order.
    """
    return docker_images(
        all_apps_dir=all_apps_dir,
        only_belonging_to_user=True,
        docker_hub_username=docker_hub_username,
    )


if __name__ == '__main__':

    parser = DockerHubArgumentParser(description='Print commands to push all container images.')
    args = parser.parse_arguments()
    docker_hub_username_ = args.docker_hub_username()

    branch = current_git_branch_name()

    for image in _docker_images_to_push(all_apps_dir=args.all_apps_dir(), docker_hub_username=docker_hub_username_):
        command = ['docker', 'push', '{}:{}'.format(image, branch)]

        if args.print_commands():
            print(' '.join(command))
        else:
            subprocess.check_call(command)
