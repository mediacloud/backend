#!/usr/bin/env python3

"""
Pull pre-built Docker images for all apps, and tag them with both the name of the current Git branch and "latest".

Usage:

    ./dev/pull.py

This script can print the commands that are going to be run instead of running them itself:

    ./dev/pull.py -p | grep solr-shard | bash

"""

import subprocess
from typing import List

from utils import docker_images, docker_tag_from_current_git_branch_name, CRPruneArgumentParser, REPO_URI


def _docker_images_to_pull(all_apps_dir: str) -> List[str]:
    """
    Return an ordered list of Docker images to pull.

    :param all_apps_dir: Directory with container subdirectories.
    :return: List of tagged Docker images to pull in that order.
    """
    return docker_images(
        all_apps_dir=all_apps_dir,
        only_belonging_to_user=False,
    )


def _docker_pull_commands(all_apps_dir: str, image_tag: str, prune_images: bool) -> List[str]:
    """
    Return an ordered list of "docker pull" commands to run in order to pull all images.

    :param all_apps_dir: Directory with container subdirectories.
    :param image_tag: Docker image tag.
    :param prune_images: True if images are to be pruned after pulling each image to clean up disk space immediately.
    :return: List of "docker pull" commands to run in order to pull all images.
    """
    commands = []

    for image in _docker_images_to_pull(all_apps_dir=all_apps_dir):

        if image.startswith(REPO_URI + '/'):

            # 1) First try to pull the image for the current branch
            # 2) if that fails (e.g. the branch is new and it hasn't yet been built and tagged on container registry), pull
            #    builds for "master" and tag them as if they were built from the current branch
            # 3) Tag the branch image (which at this point was either built from the branch or from "master") as
            #    "latest", i.e. mark them as the latest local build to be later used for rebuilding and running tests

            pull_branch = 'docker pull {image}:{tag}'.format(image=image, tag=image_tag)
            pull_master = 'docker pull {image}:master'.format(image=image)
            tag_master_as_branch = 'docker tag {image}:master {image}:{tag}'.format(image=image, tag=image_tag)
            tag_branch_as_latest = 'docker tag {image}:{tag} {image}:latest'.format(image=image, tag=image_tag)

            command = (
                    pull_branch +
                    ' || ' + '{ ' + pull_master + ' && ' + tag_master_as_branch + '; }' +
                    ' && ' + tag_branch_as_latest
            )

        else:

            # Third-party image - just pull it
            command = 'docker pull {}'.format(image)

        if prune_images:
            command += ' && docker image prune -f'

        commands.append(command)

    return commands


if __name__ == '__main__':
    parser = CRPruneArgumentParser(description='Print commands to pull all container images.')
    args = parser.parse_arguments()

    commands_ = _docker_pull_commands(
        all_apps_dir=args.all_apps_dir(),
        image_tag=docker_tag_from_current_git_branch_name(),
        prune_images=args.prune_images(),
    )

    if args.print_commands():
        for command_ in commands_:
            print(command_)

    else:
        # Attempt to pull all images, don't stop at a single failure (the image for a specific branch might simply not
        # exist yet), raise exception if at least one of the images couldn't get pulled
        last_exception = None

        for command_ in commands_:
            try:
                subprocess.check_call(command_, shell=True)
            except subprocess.CalledProcessError as ex_:
                last_exception = ex_

        if last_exception:
            raise last_exception
