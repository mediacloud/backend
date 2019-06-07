#!/usr/bin/env python3

from typing import List

from utils import docker_images, current_git_branch_name, DockerHubArgumentParser


def _docker_images_to_pull(all_apps_dir: str, docker_hub_username: str) -> List[str]:
    """
    Return an ordered list of Docker images to pull.

    :param all_apps_dir: Directory with container subdirectories.
    :param docker_hub_username: Docker Hub username.
    :return: List of tagged Docker images to pull in that order.
    """
    return docker_images(
        all_apps_dir=all_apps_dir,
        only_belonging_to_user=False,
        docker_hub_username=docker_hub_username,
    )


if __name__ == '__main__':

    parser = DockerHubArgumentParser(description='Print commands to pull all container images.')
    args = parser.parse_arguments()
    docker_hub_username_ = args.docker_hub_username()

    branch = current_git_branch_name()

    for image in _docker_images_to_pull(all_apps_dir=args.all_apps_dir(), docker_hub_username=docker_hub_username_):

        if image.startswith(docker_hub_username_ + '/'):

            # 1) First try to pull the image for the current branch
            # 2) if that fails (e.g. the branch is new and it hasn't yet been built
            #    and tagged on Docker Hub), pull builds for "master" and tag them
            #    as if they were built from the current branch
            # 3) Tag the branch image (which at this point was either built from
            #    the branch or from "master") as "latest", i.e. mark them as the
            #    latest local build to be later used for rebuilding and running
            #    tests

            pull_branch = 'docker pull {image}:{branch}'.format(
                image=image,
                branch=branch,
            )

            pull_master = 'docker pull {image}:master'.format(
                image=image,
            )

            tag_master_as_branch = 'docker tag {image}:master {image}:{branch}'.format(
                image=image,
                branch=branch,
            )

            tag_branch_as_latest = 'docker tag {image}:{branch} {image}:latest'.format(
                image=image,
                branch=branch,
            )

            print(
                pull_branch + ' || ' +
                '{ ' + pull_master + ' && ' + tag_master_as_branch + '; }' +
                ' && ' + tag_branch_as_latest
            )

        else:

            # Third-party image - just pull it
            print('docker pull {}'.format(image))
