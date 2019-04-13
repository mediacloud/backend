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


def container_dir_name_from_image_name(image_name: str, conf: DockerHubConfiguration) -> str:
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


def _image_belongs_to_username(image_name: str, conf: DockerHubConfiguration) -> bool:
    """
    Determine whether an image is hosted under a given Docker Hub username and thus has to be built.

    :param image_name: Image name (with username, prefix and version).
    :param conf: Docker Hub configuration object.
    :return: True if image is to be hosted on a Docker Hub account pointed to in configuration.
    """
    return image_name.startswith(conf.username + '/')


def _container_dependency_map(all_containers_dir: str, conf: DockerHubConfiguration) -> Dict[str, str]:
    """
    Determine which container depends on which parent image.

    :param all_containers_dir: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: Map of dependent - dependency container directory names.
    """
    if not os.path.isdir(all_containers_dir):
        raise ValueError("All containers directory does not exist: '{}'".format(all_containers_dir))

    parent_images = {}

    for container_path in glob.glob('{}/*'.format(all_containers_dir)):
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


def _ordered_dependencies_from_directory(all_containers_dir: str, conf: DockerHubConfiguration) -> List[Set[str]]:
    """
    Return a list of sets of container names to build in order.

    :param all_containers_dir: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: List of sets of container names in the order in which they should be built.
    """
    dependency_map = _container_dependency_map(all_containers_dir=all_containers_dir, conf=conf)
    ordered_dependencies = _ordered_container_dependencies(dependency_map)
    return ordered_dependencies


def docker_images(all_containers_dir: str, only_belonging_to_user: bool, conf: DockerHubConfiguration) -> List[str]:
    """
    Return a list of Docker images to pull / build / push in the correct order.

    :param all_containers_dir: Directory with container subdirectories.
    :param only_belonging_to_user: If True, return only the images that belong to the configured user.
    :param conf: Docker Hub configuration object.
    :return: List of tagged Docker images to pull / build / push in the correct order.
    """
    ordered_dependencies = _ordered_dependencies_from_directory(all_containers_dir=all_containers_dir, conf=conf)

    images = []

    for level_dependencies in ordered_dependencies:
        for dependency in sorted(level_dependencies):

            if only_belonging_to_user:
                if not _image_belongs_to_username(image_name=dependency, conf=conf):
                    continue

            images.append(dependency)

    return images


def argument_parser(description: str) -> argparse.ArgumentParser:
    """
    Create and return an argument parser object to use for reading command's arguments.

    :param description: Description of the script to print when "--help" is passed.
    :return: Argument parser object.
    """

    default_conf = DefaultDockerHubConfiguration()

    parser = argparse.ArgumentParser(
        description=description,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument('-c', '--all_containers_dir', required=True, type=str,
                        help='Directory with container subdirectories.')
    parser.add_argument('-u', '--dockerhub_user', required=False, type=str, default=default_conf.username,
                        help='Docker Hub user that is hosting the images.')
    parser.add_argument('-p', '--image_prefix', required=False, type=str, default=default_conf.image_prefix,
                        help="Prefix to add to built images.")
    parser.add_argument('-s', '--image_version', required=False, type=str, default=default_conf.image_version,
                        help="Version to add to built images.")

    return parser


def docker_hub_configuration_from_arguments(args: argparse.Namespace) -> DockerHubConfiguration:
    """
    Create and return a Docker Hub configuration object from an argument parser object.

    :param args: argparse arguments.
    :return: DockerHubConfiguration object.
    """

    if not os.path.isfile(os.path.join(args.all_containers_dir, 'docker-compose.yml.dist')):
        raise ValueError("Invalid directory with container subdirectories '{}'.".format(args.all_containers_dir))

    return DockerHubConfiguration(
        username=args.dockerhub_user,
        image_prefix=args.image_prefix,
        image_version=args.image_version,
    )
