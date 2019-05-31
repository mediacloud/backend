#!/usr/bin/env python3

from typing import List

from utils import (
    DockerHubConfiguration,
    docker_images,
    current_git_branch_name,
    DockerHubArgumentParser,
)


def _docker_images_to_pull(all_apps_dir: str, conf: DockerHubConfiguration) -> List[str]:
    """
    Return an ordered list of Docker images to pull.

    :param all_apps_dir: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: List of tagged Docker images to pull in that order.
    """
    return docker_images(all_apps_dir=all_apps_dir, only_belonging_to_user=False, conf=conf)


if __name__ == '__main__':

    parser = DockerHubArgumentParser(description='Print commands to pull all container images.')
    args = parser.parse_arguments()
    conf_ = args.docker_hub_configuration()

    branch = current_git_branch_name()

    for image in _docker_images_to_pull(all_apps_dir=args.all_apps_dir(), conf=conf_):
        # First try to pull the image for the current branch, and if that fails (e.g. the branch
        # is new and it hasn't yet been built and tagged on Docker Hub), pull builds for "master"
        # and tag them as if they were of the current branch
        print(
            'docker pull {image}:{branch} || {{ docker pull {image}:master && docker tag {image}:master {image}:{branch} }}'.format(
                image=image,
                branch=branch,
            )
        )
