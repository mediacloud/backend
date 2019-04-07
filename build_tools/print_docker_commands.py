#!/usr/bin/env python3

"""
Print out Docker commands in an optimal order for all of the managed containers.
"""

import argparse
import glob
import os
import re
from typing import Dict, List, Set


class DockerHubConfiguration(object):
    """
    Docker Hub configuration.
    """

    __slots__ = [
        'username',
        'image_prefix',
        'image_version',
    ]

    def __init__(self, username: str, image_prefix: str, image_version: str):
        """
        Constructor.

        :param username: Docker Hub username where the images are hosted.
        :param image_prefix: Prefix to add to the image tag.
        :param image_version: Version to add to the image tag.
        """
        if not re.match(r'^[\w\-_]+$', username):
            raise ValueError("Docker Hub username is invalid: {}".format(username))

        if not re.match(r'^[\w]+$', image_prefix):
            raise ValueError("Image prefix is invalid: {}".format(image_prefix))

        if not re.match(r'^[\w\-_]+$', image_version):
            raise ValueError("Image version is invalid: {}".format(image_version))

        self.username = username
        self.image_prefix = image_prefix
        self.image_version = image_version


class DefaultDockerHubConfiguration(DockerHubConfiguration):
    """
    Default Docker Hub configuration.
    """

    def __init__(self):
        """
        Initializes object with default values.
        """
        super().__init__(username='dockermediacloud', image_prefix='mediacloud', image_version='latest')


def _docker_parent_image_name(dockerfile_path: str) -> str:
    """
    Return Docker parent image name (FROM value) from a Dockerfile.

    :param dockerfile_path: Path to Dockerfile to parse.
    :return: FROM value as found in the Dockerfile.
    """
    if not os.path.isfile(dockerfile_path):
        raise ValueError("Path is not Dockerfile: {}".format(dockerfile_path))

    with open(dockerfile_path, mode='r', encoding='utf-8') as f:
        for line in f:
            if line.startswith('FROM '):
                match = re.search(r'^FROM (.+?)$', line)

                if not match:
                    raise ValueError("Can't match FROM in Dockerfile '{}'.".format(dockerfile_path))

                parent_image = match.group(1)
                assert parent_image, "Parent image should be set at this point."

                return parent_image

    raise ValueError("No FROM clause found in {}.".format(dockerfile_path))


def _image_name_from_container_name(container_name: str, conf: DockerHubConfiguration) -> str:
    """
    Convert container directory name to an image name.

    :param container_name: Container directory name.
    :param conf: Docker Hub configuration object.
    :return: Image name (with username, prefix and version).
    """
    if not re.match(r'^[\w\-]+$', container_name):
        raise ValueError("Container name is invalid: {}".format(container_name))

    return '{username}/{image_prefix}-{container_name}:{image_version}'.format(
        username=conf.username,
        image_prefix=conf.image_prefix,
        container_name=container_name,
        image_version=conf.image_version,
    )


def _container_dir_name_from_image_name(image_name: str, conf: DockerHubConfiguration) -> str:
    """
    Convert image name to a container directory name.

    :param image_name: Image name (with username, prefix and version).
    :param conf: Docker Hub configuration object.
    :return: Container directory name.
    """
    container_name = image_name

    expected_prefix = conf.username + '/'
    if not container_name.startswith(expected_prefix):
        raise ValueError("Image name '{}' is expected to start with '{}/'.".format(image_name, conf.username))
    container_name = container_name[len(expected_prefix):]

    expected_prefix = conf.image_prefix + '-'
    if not container_name.startswith(expected_prefix):
        raise ValueError("Image name '{}' is expected to have prefix '{}-'.".format(image_name, conf.image_prefix))
    container_name = container_name[len(expected_prefix):]

    expected_suffix = ':' + conf.image_version
    if not container_name.endswith(expected_suffix):
        raise ValueError("Image name '{}' is expected to end with ':{}'.".format(image_name, conf.image_version))
    container_name = container_name[:len(expected_suffix) * -1]

    return container_name


def _image_belongs_to_username(image_name: str, conf: DockerHubConfiguration) -> bool:
    """
    Determine whether an image is hosted under a given Docker Hub username and thus has to be built.

    :param image_name: Image name (with username, prefix and version).
    :param conf: Docker Hub configuration object.
    :return: True if image is to be hosted on a Docker Hub account pointed to in configuration.
    """
    return image_name.startswith(conf.username + '/')


def _container_dependency_map(container_directory: str, conf: DockerHubConfiguration) -> Dict[str, str]:
    """
    Determine which container depends on which parent image.

    :param container_directory: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: Map of dependent - dependency container directory names.
    """
    if not os.path.isdir(container_directory):
        raise ValueError("Container directory does not exist: '{}'".format(container_directory))

    parent_images = {}

    for container_path in glob.glob('{}/*'.format(container_directory)):
        if os.path.isdir(container_path):
            container_name = os.path.basename(container_path)
            image_name = _image_name_from_container_name(container_name=container_name, conf=conf)

            dockerfile_path = os.path.join(container_path, 'Dockerfile')
            parent_docker_image = _docker_parent_image_name(dockerfile_path)

            parent_images[image_name] = parent_docker_image

    return parent_images


def _ordered_container_dependencies(dependencies: Dict[str, str]) -> List[Set[str]]:
    """
    For dependent container - container dependency pairs, return a list of sets of container names to build in order.

    Adapted from https://code.activestate.com/recipes/576570-dependency-resolver/

    :param dependencies: Map of dependent container name - container dependency name.
    :return: List of sets of container names in the order in which they should be built.
    """

    tree = []

    while len(dependencies):

        level_dependencies = set()

        for dependent, dependency in dependencies.items():

            # Values not in keys
            if not dependencies.get(dependency, None):
                if dependency:
                    level_dependencies.add(dependency)

            # Keys with value set to None
            if not dependency:
                level_dependencies.add(dependent)

        tree.append(level_dependencies)

        new_dependencies = dict()

        for dependent, dependency in dependencies.items():
            if dependent not in level_dependencies:
                new_dependencies[dependent] = None if dependency in level_dependencies else dependency

        dependencies = new_dependencies

    return tree


def _ordered_dependencies_from_directory(container_directory: str, conf: DockerHubConfiguration) -> List[Set[str]]:
    """
    Return a list of sets of container names to build in order.

    :param container_directory: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: List of sets of container names in the order in which they should be built.
    """
    dependency_map = _container_dependency_map(container_directory=container_directory, conf=conf)
    ordered_dependencies = _ordered_container_dependencies(dependency_map)
    return ordered_dependencies


def docker_images_to_pull(container_directory: str, conf: DockerHubConfiguration) -> List[str]:
    """
    Return an ordered list of Docker images to pull.

    :param container_directory: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: List of tagged Docker images to pull in that order.
    """
    ordered_dependencies = _ordered_dependencies_from_directory(container_directory=container_directory, conf=conf)

    images_to_pull = []

    for level_dependencies in ordered_dependencies:
        for dependency in sorted(level_dependencies):
            images_to_pull.append(dependency)

    return images_to_pull


def docker_images_to_push(container_directory: str, conf: DockerHubConfiguration) -> List[str]:
    """
    Return an ordered list of Docker images to push.

    :param container_directory: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: List of tagged Docker images to push in that order.
    """
    images_to_push = []

    for image_to_push in docker_images_to_pull(container_directory=container_directory, conf=conf):
        if _image_belongs_to_username(image_name=image_to_push, conf=conf):
            images_to_push.append(image_to_push)

    return images_to_push


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


def docker_images_to_build(container_directory: str, conf: DockerHubConfiguration) -> List[DockerImageToBuild]:
    """
    Return an ordered list of Docker images to build.

    :param container_directory: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: List of Docker images to build in that order.
    """

    ordered_dependencies = _ordered_dependencies_from_directory(container_directory=container_directory, conf=conf)

    images_to_build = []

    for level_dependencies in ordered_dependencies:
        for dependency in sorted(level_dependencies):
            if _image_belongs_to_username(image_name=dependency, conf=conf):
                container_name = _container_dir_name_from_image_name(image_name=dependency, conf=conf)
                container_path = os.path.join(container_directory, container_name)

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

    default_config = DefaultDockerHubConfiguration()

    parser = argparse.ArgumentParser(
        description='Print Docker commands to run to pull / build / push all of the containers.',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument('command', type=str, choices=['pull', 'build', 'push'], help='Docker command to run.')

    parser.add_argument('-c', '--container_dir', required=True, type=str,
                        help='Directory with container subdirectories.')
    parser.add_argument('-u', '--dockerhub_user', required=False, type=str, default=default_config.username,
                        help='Docker Hub user that is hosting the images.')
    parser.add_argument('-p', '--image_prefix', required=False, type=str, default=default_config.image_prefix,
                        help="Prefix to add to built images.")
    parser.add_argument('-s', '--image_version', required=False, type=str, default=default_config.image_version,
                        help="Version to add to built images.")
    args = parser.parse_args()

    if not os.path.isfile(os.path.join(args.container_dir, 'docker-compose.yml.dist')):
        raise ValueError("Invalid directory with container subdirectories '{}'.".format(args.container_dir))

    config = DockerHubConfiguration(username=args.dockerhub_user,
                                    image_prefix=args.image_prefix,
                                    image_version=args.image_version)

    if args.command == 'pull':
        for image in docker_images_to_pull(container_directory=args.container_dir, conf=config):
            print('docker pull {}'.format(image))

    elif args.command == 'build':
        for image in docker_images_to_build(container_directory=args.container_dir, conf=config):
            print(
                (
                    # Try building with and without --cache-from because the image might not have been pulled / might
                    # not exist at all
                    'docker build --cache-from {image_name} --tag {image_name} {container_path}'
                    ' || '
                    'docker build --tag {image_name} {container_path}'

                ).format(
                    image_name=image.tag,
                    container_path=image.path,
                ))

    elif args.command == 'push':
        for image in docker_images_to_push(container_directory=args.container_dir, conf=config):
            print('docker push {}'.format(image))

    else:
        raise ValueError("Unsupported command '{}'.".format(args.action))
