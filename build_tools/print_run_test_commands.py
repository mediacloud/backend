#!/usr/bin/env python3

import os
import re
import tempfile
from pathlib import Path
from typing import List

# Given that docker-compose is present, we assume that PyYAML is installed

from utils import DockerArgumentParser, DockerArguments

try:
    from yaml import safe_load as load_yaml
except ModuleNotFoundError:
    raise ImportError("Please install PyYAML.")

DOCKER_COMPOSE_FILENAME = 'docker-compose.tests.yml'
"""Filename of 'docker-compose.yml' used for running tests."""


class InvalidDockerComposeYMLException(Exception):
    """Exception that gets thrown on docker-compose.yml errors."""


def _validate_docker_compose_yml(docker_compose_path: str, container_name: str) -> None:
    """
    Validate docker-compose.yml, throw exception on errors
    :param docker_compose_path: Path to docker-compose.yml
    """

    with open(docker_compose_path, mode='r', encoding='utf-8') as f:

        try:
            yaml_root = load_yaml(f)
        except Exception as ex:
            raise InvalidDockerComposeYMLException("Unable to load YAML file: {}".format(ex))

        if 'services' not in yaml_root:
            raise InvalidDockerComposeYMLException("No 'services' key under root.")

        if container_name not in yaml_root['services']:
            raise InvalidDockerComposeYMLException("No '{} key under 'services'.".format(container_name))


def _project_name(container_name: str, tests_dir: str, test_file: str) -> str:
    """
    Return docker-compose "project name" for a specific test.

    :param container_name: Directory of a specific container that is being tested.
    :param test_file: Test file that is being run.
    :return: docker-compose project name.
    """
    shortened_test_file = test_file[len(tests_dir):]
    shortened_test_file = os.path.splitext(shortened_test_file)[0]
    if shortened_test_file.startswith('/'):
        shortened_test_file = shortened_test_file[1:]

    project_name = 'test-{}-{}'.format(
        container_name,
        re.sub(r'\W+', '_', shortened_test_file, flags=re.ASCII).lower(),
    )

    return project_name


def docker_test_commands(all_containers_dir: str, test_file: str, dummy: bool = False) -> List[List[str]]:
    """
    Return list commands to execute in order to run all tests in a single test file.

    :param all_containers_dir: Directory with container subdirectories.
    :param test_file: Perl or Python test file.
    :param dummy: If True, set up Compose environment and sleep indefinitely instead of running the test.
    :return: List of commands (as lists) to execute in order to run tests in a test file.
    """
    if not os.path.isfile(test_file):
        raise ValueError("Test file '{}' does not exist.".format(test_file))
    if not os.path.isdir(all_containers_dir):
        raise ValueError("Containers directory '{}' does not exist.".format(all_containers_dir))

    all_containers_dir = os.path.abspath(all_containers_dir)
    test_file = os.path.abspath(test_file)

    if not test_file.startswith(all_containers_dir):
        raise ValueError("Test file '{}' is not in containers directory '{}'.".format(test_file, all_containers_dir))

    test_file_extension = os.path.splitext(test_file)[1]
    if test_file_extension not in ['.py', '.t']:
        raise ValueError("Test file '{}' doesn't look like one.".format(test_file))

    test_file_relative_path = test_file[(len(all_containers_dir)):]
    test_file_relative_path_dirs = Path(test_file_relative_path).parts

    container_dirname = test_file_relative_path_dirs[1]
    container_dir = os.path.join(all_containers_dir, container_dirname)
    container_name = "mc_" + container_dirname.replace('-', '_')

    tests_dir = os.path.join(container_dir, 'tests')
    if not os.path.isdir(tests_dir):
        raise ValueError("Test file '{}' is not located in '{}' subdirectory.".format(test_file, tests_dir))

    docker_compose_path = os.path.join(container_dir, DOCKER_COMPOSE_FILENAME)
    if not os.path.isfile(docker_compose_path):
        raise ValueError("docker-compose configuration was not found at '{}'.".format(docker_compose_path))

    try:
        _validate_docker_compose_yml(docker_compose_path=docker_compose_path, container_name=container_name)
    except InvalidDockerComposeYMLException as ex:
        raise ValueError("docker-compose configuration in '{}' is invalid: {}".format(docker_compose_path, ex))

    project_name = _project_name(container_name=container_name, tests_dir=tests_dir, test_file=test_file)

    commands = list()

    docker_compose_override_path = os.path.join(tempfile.mkdtemp(), 'docker-compose.tests-override.yml')

    if dummy:
        test_command = 'sleep infinity'

    else:
        test_path_in_container = '/opt/mediacloud/tests' + test_file[len(tests_dir):]

        if test_file.endswith('.py'):
            test_command = 'py.test --verbose ' + test_path_in_container
        elif test_file.endswith('.t'):
            test_command = 'prove ' + test_path_in_container
        else:
            raise ValueError("Not sure how to run this test: {}".format(test_path_in_container))

    commands.append(['touch', docker_compose_override_path])
    commands.append(['echo', "'version: \"3.7\"'", '>>', docker_compose_override_path])
    commands.append(['echo', "'services:'", '>>', docker_compose_override_path])
    commands.append(['echo', "'    {}:'".format(container_name), '>>', docker_compose_override_path])
    commands.append(['echo', "'        command: \"{}\"'".format(test_command), '>>', docker_compose_override_path])

    commands.append([
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
        '--file', docker_compose_override_path,
        'up',
        '--no-start',
        '--renew-anon-volumes',
        '--force-recreate',
    ])

    # Not "docker-compose run" because:
    # * it doesn't recreate containers if they already exist
    # * it doesn't clean up volumes after exit (additional "docker-compose down" is needed)
    # * after command in the main container exits, it doesn't stop the rest of the containers
    commands.append([
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
        '--file', docker_compose_override_path,
        'up',
        '--abort-on-container-exit',
        '--exit-code-from', container_name,
    ])

    commands.append([
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
        'down',
        '--volumes',
    ])

    return commands


class DockerRunTestArguments(DockerArguments):
    """
    Arguments with a test file path.
    """

    def test_file(self) -> str:
        """
        Return path to file to test.

        :return: Path to test file.
        """
        return self._args.test_file

    def dummy(self) -> bool:
        """
        Return True if instead of running the test, we should set up the Compose environment and then sleep.
        :return: True if instead of running the test, we should set up the Compose environment and then sleep.
        """
        return self._args.dummy


class DockerRunTestArgumentParser(DockerArgumentParser):
    """
    Argument parser that includes a path to test file.
    """

    def __init__(self, description: str):
        """
        Constructor.

        :param description: Description of the script to print when "--help" is passed.
        """
        super().__init__(description=description)
        self._parser.add_argument('test_file',
                                  help='Perl or Python test file.')
        self._parser.add_argument('-d', '--dummy', action='store_true',
                                  help="Don't actually run the test, instead sleep for infinity.")

    def parse_arguments(self) -> DockerRunTestArguments:
        """
        Parse arguments and return an object with parsed arguments.

        :return: DockerRunTestArguments object.
        """
        return DockerRunTestArguments(self._parser.parse_args())


if __name__ == '__main__':
    parser = DockerRunTestArgumentParser(description='Print commands to run tests in a single test file.')
    args = parser.parse_arguments()

    for command_ in docker_test_commands(all_containers_dir=args.all_containers_dir(),
                                         test_file=args.test_file(),
                                         dummy=args.dummy()):
        print(' '.join(command_))
