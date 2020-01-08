#!/usr/bin/env python3

"""
Push Docker images for all apps that are tagged with the name of the current Git branch.

Usage:

    ./dev/push.py

This script can print the commands that are going to be run instead of running them itself:

    # "bash -e" because we want to stop on the first error
    ./dev/push.py -p | grep solr-shard | bash -e

"""

import subprocess
from typing import List

from utils import docker_images, docker_tag_from_current_git_branch_name, DockerArgumentParser


def _docker_images_to_push(all_apps_dir: str) -> List[str]:
    """
    Return an ordered list of Docker images to push.

    :param all_apps_dir: Directory with container subdirectories.
    :return: List of tagged Docker images to push in that order.
    """
    return docker_images(
        all_apps_dir=all_apps_dir,
        only_belonging_to_user=True,
    )


if __name__ == '__main__':

    parser = DockerArgumentParser(description='Print commands to push all container images.')
    args = parser.parse_arguments()

    image_tag = docker_tag_from_current_git_branch_name()

    for image in _docker_images_to_push(all_apps_dir=args.all_apps_dir()):
        command = ['docker', 'push', '{}:{}'.format(image, image_tag)]

        if args.print_commands():
            print(' '.join(command))
        else:
            # Run push commands, stop at the first failed build
            subprocess.check_call(command)
