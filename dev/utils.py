import argparse
import glob
import os
import re
import subprocess
from typing import Dict, List, Set


class DockerHubConfiguration(object):
    """
    Docker Hub configuration.
    """

    __slots__ = [
        'username',
    ]

    def __init__(self, username: str):
        """
        Constructor.

        :param username: Docker Hub username where the images are hosted.
        """
        if not re.match(r'^[\w\-_]+$', username):
            raise ValueError("Docker Hub username is invalid: {}".format(username))

        self.username = username


class DefaultDockerHubConfiguration(DockerHubConfiguration):
    """
    Default Docker Hub configuration.
    """

    def __init__(self):
        """
        Initializes object with default values.
        """
        super().__init__(username='dockermediacloud')


def _image_name_from_container_name(container_name: str, conf: DockerHubConfiguration) -> str:
    """
    Convert container directory name to an image name.

    :param container_name: Container directory name.
    :param conf: Docker Hub configuration object.
    :return: Image name (with username, prefix and version).
    """
    if not re.match(r'^[\w\-]+$', container_name):
        raise ValueError("Container name is invalid: {}".format(container_name))

    return '{username}/{container_name}'.format(
        username=conf.username,
        container_name=container_name,
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

                # Remove version tag
                parent_image = re.sub(r':(.+?)$', '', parent_image)

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


def _container_dependency_map(all_apps_dir: str, conf: DockerHubConfiguration) -> Dict[str, str]:
    """
    Determine which container depends on which parent image.

    :param all_apps_dir: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: Map of dependent - dependency container directory names.
    """
    if not os.path.isdir(all_apps_dir):
        raise ValueError("All apps directory does not exist: '{}'".format(all_apps_dir))

    parent_images = {}

    for container_path in glob.glob('{}/*'.format(all_apps_dir)):
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


def _ordered_dependencies_from_directory(all_apps_dir: str, conf: DockerHubConfiguration) -> List[Set[str]]:
    """
    Return a list of sets of container names to build in order.

    :param all_apps_dir: Directory with container subdirectories.
    :param conf: Docker Hub configuration object.
    :return: List of sets of container names in the order in which they should be built.
    """
    dependency_map = _container_dependency_map(all_apps_dir=all_apps_dir, conf=conf)
    ordered_dependencies = _ordered_container_dependencies(dependency_map)
    return ordered_dependencies


def docker_images(all_apps_dir: str, only_belonging_to_user: bool, conf: DockerHubConfiguration) -> List[str]:
    """
    Return a list of Docker images to pull / build / push in the correct order.

    :param all_apps_dir: Directory with container subdirectories.
    :param only_belonging_to_user: If True, return only the images that belong to the configured user.
    :param conf: Docker Hub configuration object.
    :return: List of tagged Docker images to pull / build / push in the correct order.
    """
    ordered_dependencies = _ordered_dependencies_from_directory(all_apps_dir=all_apps_dir, conf=conf)

    images = []

    for level_dependencies in ordered_dependencies:
        for dependency in sorted(level_dependencies):

            if only_belonging_to_user:
                if not _image_belongs_to_username(image_name=dependency, conf=conf):
                    continue

            images.append(dependency)

    return images


def current_git_branch_name() -> str:
    pwd = os.path.dirname(os.path.realpath(__file__))
    result = subprocess.run(
        ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
        cwd=pwd,
        stdout=subprocess.PIPE,
    )
    branch_name = result.stdout.decode('utf-8').strip()
    return branch_name


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

    def all_apps_dir(self) -> str:
        """
        Return directory with container subdirectories.

        :return Directory with container subdirectories.
        """
        return self._args.all_apps_dir


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

    def parse_arguments(self) -> DockerArguments:
        """
        Parse arguments and return an object with parsed arguments.

        :return: DockerArguments (or subclass) object.
        """
        return DockerArguments(self._parser.parse_args())


class DockerHubArguments(DockerArguments):
    """
    Arguments that include Docker Hub credentials.
    """

    def docker_hub_configuration(self) -> DockerHubConfiguration:
        """
        Return a Docker Hub configuration object from an argument parser object.

        :return: DockerHubConfiguration object.
        """

        if not os.path.isfile(os.path.join(self.all_apps_dir(), 'docker-compose.yml.dist')):
            raise ValueError("Invalid directory with container subdirectories '{}'.".format(self.all_apps_dir()))

        return DockerHubConfiguration(
            username=self._args.dockerhub_user,
        )


class DockerHubArgumentParser(DockerArgumentParser):
    """Argument parser which requires Docker Hub credentials."""

    def __init__(self, description: str):
        """
        Constructor.

        :param description: Description of the script to print when "--help" is passed.
        """
        super().__init__(description=description)

        default_conf = DefaultDockerHubConfiguration()

        self._parser.add_argument('-u', '--dockerhub_user', required=False, type=str, default=default_conf.username,
                                  help='Docker Hub user that is hosting the images.')

    def parse_arguments(self) -> DockerHubArguments:
        """
        Parse arguments and return an object with parsed arguments.

        :return: DockerHubArguments object.
        """
        return DockerHubArguments(self._parser.parse_args())
