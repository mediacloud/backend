"""
Various utilities for pull / build / push scripts.
"""

import argparse
import glob
import os
import re
import subprocess
from typing import Dict, List, Set


DOCKERHUB_USER = 'dockermediacloud'


def _image_name_from_container_name(container_name: str) -> str:
    """
    Convert container directory name to an image name.

    :param container_name: Container directory name.
    :return: Image name (with username, prefix and version).
    """
    if not re.match(r'^[\w\-]+$', container_name):
        raise ValueError("Container name is invalid: {}".format(container_name))

    return '{username}/{container_name}'.format(
        username=DOCKERHUB_USER,
        container_name=container_name,
    )


def container_dir_name_from_image_name(image_name: str) -> str:
    """
    Convert image name to a container directory name.

    :param image_name: Image name (with username, prefix and version).
    :return: Container directory name.
    """
    container_name = image_name

    expected_prefix = DOCKERHUB_USER + '/'
    if not container_name.startswith(expected_prefix):
        raise ValueError("Image name '{}' is expected to start with '{}/'.".format(image_name, DOCKERHUB_USER))
    container_name = container_name[len(expected_prefix):]

    # Remove version
    container_name = re.sub(r':(.+?)$', '', container_name)

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

                # Remove version tag if it's one of our own images
                if parent_image.startswith(DOCKERHUB_USER + '/'):
                    parent_image = re.sub(r':(.+?)$', '', parent_image)

                return parent_image

    raise ValueError("No FROM clause found in {}.".format(dockerfile_path))


def _image_belongs_to_username(image_name: str) -> bool:
    """
    Determine whether an image is hosted under a given Docker Hub username and thus has to be built.

    :param image_name: Image name (with username, prefix and version).
    :return: True if image is to be hosted on a Docker Hub account pointed to in configuration.
    """
    return image_name.startswith(DOCKERHUB_USER + '/')


def _container_dependency_map(all_apps_dir: str) -> Dict[str, str]:
    """
    Determine which container depends on which parent image.

    :param all_apps_dir: Directory with container subdirectories.
    :return: Map of dependent - dependency container directory names.
    """
    if not os.path.isdir(all_apps_dir):
        raise ValueError("All apps directory does not exist: '{}'".format(all_apps_dir))

    parent_images = {}

    for container_path in glob.glob('{}/*'.format(all_apps_dir)):
        if os.path.isdir(container_path):
            container_name = os.path.basename(container_path)
            image_name = _image_name_from_container_name(
                container_name=container_name,
            )

            dockerfile_path = os.path.join(container_path, 'Dockerfile')
            parent_docker_image = _docker_parent_image_name(
                dockerfile_path=dockerfile_path,
            )

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


def _ordered_dependencies_from_directory(all_apps_dir: str) -> List[Set[str]]:
    """
    Return a list of sets of container names to build in order.

    :param all_apps_dir: Directory with container subdirectories.
    :return: List of sets of container names in the order in which they should be built.
    """
    dependency_map = _container_dependency_map(all_apps_dir=all_apps_dir)
    ordered_dependencies = _ordered_container_dependencies(dependency_map)
    return ordered_dependencies


def docker_images(all_apps_dir: str, only_belonging_to_user: bool) -> List[str]:
    """
    Return a list of Docker images to pull / build / push in the correct order.

    :param all_apps_dir: Directory with container subdirectories.
    :param only_belonging_to_user: If True, return only the images that belong to the configured user.
    :return: List of tagged Docker images to pull / build / push in the correct order.
    """
    ordered_dependencies = _ordered_dependencies_from_directory(
        all_apps_dir=all_apps_dir,
    )

    images = []

    for level_dependencies in ordered_dependencies:
        for dependency in sorted(level_dependencies):

            if only_belonging_to_user:
                if not _image_belongs_to_username(image_name=dependency):
                    continue

            images.append(dependency)

    return images


def __current_git_branch_name() -> str:
    """
    Return Git branch name that the commit from HEAD belongs to.

    :return: Best guess for a branch name that the latest commit belongs to.
    """
    pwd = os.path.dirname(os.path.realpath(__file__))
    result = subprocess.run(
        ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
        cwd=pwd,
        stdout=subprocess.PIPE,
    )
    branch_name = result.stdout.decode('utf-8').strip()

    # Azure Pipelines checks out a specific commit and sets it as HEAD, so find at least one branch that the commit
    # belongs to
    if branch_name == 'HEAD':

        result = subprocess.run(
            ['git', 'rev-parse', 'HEAD'],
            cwd=pwd,
            stdout=subprocess.PIPE,
        )
        last_commit_hash = result.stdout.decode('utf-8').strip()
        assert len(last_commit_hash) == 40, "Last commit hash can't be empty."

        result = subprocess.run(
            ['git', 'name-rev', last_commit_hash],
            cwd=pwd,
            stdout=subprocess.PIPE,
        )
        branch_name = result.stdout.decode('utf-8').strip()
        branch_name = re.split(r'\s', branch_name)[1]

        if branch_name.startswith('remotes/origin/'):
            branch_name = re.sub(r'^remotes/origin/', '', branch_name)

        assert branch_name, "Branch name should be set."

    # Some Azure weirdness
    branch_name = branch_name.replace('~1', '')

    return branch_name


def docker_tag_from_current_git_branch_name() -> str:
    """
    Read the current Git branch name, and convert it to Docker tag.
    :return: Docker tag.
    """
    return __current_git_branch_name().replace('/', '_')


class DockerArguments(object):
    """
    Basic arguments.
    """

    __slots__ = [
        # argparse.Namespace object
        '_args',
    ]

    def __init__(self, args: argparse.Namespace):
        """
        Constructor.

        :param args: argparse.Namespace object.
        """
        self._args = args

        if not os.path.isfile(os.path.join(self.all_apps_dir(), 'docker-compose.dist.yml')):
            raise ValueError("Invalid directory with container subdirectories '{}'.".format(self.all_apps_dir()))

    def all_apps_dir(self) -> str:
        """
        Return directory with container subdirectories.

        :return Directory with container subdirectories.
        """
        return self._args.all_apps_dir

    def print_commands(self) -> bool:
        """
        Return True if commands are to be printed to STDOUT instead of being executed.

        :return: True if commands are to be printed instead of being executed.
        """
        return self._args.print_commands


class DockerArgumentParser(object):
    """
    Basic argument parser.
    """

    __slots__ = [
        # argparse.ArgumentParser object
        '_parser',
    ]

    def __init__(self, description: str):
        """
        Create and return an argument parser object to use for reading command's arguments.

        :param description: Description of the script to print when "--help" is passed.
        """
        self._parser = argparse.ArgumentParser(
            description=description,
            formatter_class=argparse.ArgumentDefaultsHelpFormatter,
        )

        args = [
            '-c', '--all_apps_dir',
        ]
        kwargs = {
            'type': str,
            'help': 'Directory with container subdirectories.',
        }

        pwd = os.path.dirname(os.path.realpath(__file__))
        expected_apps_dir = os.path.join(pwd, '../', 'apps')
        if os.path.isdir(expected_apps_dir):
            kwargs['default'] = expected_apps_dir
        else:
            kwargs['required'] = True

        self._parser.add_argument(*args, **kwargs)

        self._parser.add_argument('-p', '--print_commands', action='store_true',
                                  help="Print commands that are to be executed instead of executing them.")

    def parse_arguments(self) -> DockerArguments:
        """
        Parse arguments and return an object with parsed arguments.

        :return: DockerArguments (or subclass) object.
        """
        return DockerArguments(self._parser.parse_args())


class DockerComposeArguments(DockerArguments):
    """
    Arguments for scripts that use Docker Compose.
    """

    def verbose(self) -> bool:
        """
        Return True if docker-compose's output should be more verbose.

        :return: True if docker-compose's output should be more verbose.
        """
        return self._args.verbose


class DockerComposeArgumentParser(DockerArgumentParser):
    """Argument parser for scripts that use Docker Compose."""

    def __init__(self, description: str):
        """
        Constructor.

        :param description: Description of the script to print when "--help" is passed.
        """
        super().__init__(description=description)

        self._parser.add_argument('-v', '--verbose', action='store_true',
                                  help='Print messages about starting and stopping containers.')

    def parse_arguments(self) -> DockerComposeArguments:
        """
        Parse arguments and return an object with parsed arguments.

        :return: DockerComposeArguments object.
        """
        return DockerComposeArguments(self._parser.parse_args())


class DockerHubPruneArguments(DockerArguments):
    """
    Arguments that include Docker Hub credentials and whether to prune images.
    """

    def prune_images(self) -> bool:
        """
        Return True if images are to be pruned after pulling / building.

        :return: True if images are to be pruned after pulling / building.
        """
        return self._args.prune_images


class DockerHubPruneArgumentParser(DockerArgumentParser):
    """Argument parser which requires Docker Hub credentials and allows users to prune images."""

    def __init__(self, description: str):
        """
        Constructor.

        :param description: Description of the script to print when "--help" is passed.
        """
        super().__init__(description=description)

        self._parser.add_argument('-r', '--prune_images', action='store_true',
                                  help='Prune images after pulling / building to clean up disk space immediately.')

    def parse_arguments(self) -> DockerHubPruneArguments:
        """
        Parse arguments and return an object with parsed arguments.

        :return: DockerHubPruneArguments object.
        """
        return DockerHubPruneArguments(self._parser.parse_args())
