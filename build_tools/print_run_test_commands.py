#!/usr/bin/env python3

import argparse
import os
import re
from pathlib import Path
from typing import List

# Given that docker-compose is present, we assume that PyYAML is installed
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

    expected_container_command = 'sleep infinity'

    with open(docker_compose_path, mode='r', encoding='utf-8') as f:

        try:
            yaml_root = load_yaml(f)
        except Exception as ex:
            raise InvalidDockerComposeYMLException("Unable to load YAML file: {}".format(ex))

        if 'services' not in yaml_root:
            raise InvalidDockerComposeYMLException("No 'services' key under root.")

        if container_name not in yaml_root['services']:
            raise InvalidDockerComposeYMLException("No '{} key under 'services'.".format(container_name))

        if yaml_root['services'][container_name].get('command', None) != expected_container_command:
            raise InvalidDockerComposeYMLException("'command' of '{}' is not '{}'.".format(
                container_name,
                expected_container_command,
            ))


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
        re.sub(r'\W+', '_', shortened_test_file, flags=re.ASCII),
    )

    return project_name


def docker_test_commands(all_containers_dir: str, test_file: str) -> List[List[str]]:
    """
    Return list commands to execute in order to run all tests in a single test file.

    :param all_containers_dir: Directory with container subdirectories.
    :param test_file: Perl or Python test file.
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

    if not os.access(test_file, os.X_OK):
        raise ValueError("Test file '{}' is not executable.".format(test_file))

    with open(test_file, mode='r', encoding='utf-8') as f:
        first_line = f.readline()
        if not first_line.startswith('#!'):
            raise ValueError("Test file '{}' does not have a shebang line.".format(test_file))

    test_file_relative_path = test_file[(len(all_containers_dir)):]
    test_file_relative_path_dirs = Path(test_file_relative_path).parts

    container_dirname = test_file_relative_path_dirs[1]
    container_dir = os.path.join(all_containers_dir, container_dirname)
    container_name = "mc_" + container_dirname

    tests_dir = os.path.join(container_dir, 'tests')
    if not os.path.isdir(tests_dir):
        raise ValueError("Test file '{}' is not located in '{}' subdirectory.".format(test_file, tests_dir))

    docker_compose_path = os.path.join(container_dir, 'tests', DOCKER_COMPOSE_FILENAME)
    if not os.path.isfile(docker_compose_path):
        raise ValueError("docker-compose configuration was not found at '{}'.".format(docker_compose_path))

    try:
        _validate_docker_compose_yml(docker_compose_path=docker_compose_path, container_name=container_name)
    except InvalidDockerComposeYMLException as ex:
        raise ValueError("docker-compose configuration in '{}' is invalid: {}".format(docker_compose_path, ex))

    project_name = _project_name(container_name=container_name, tests_dir=tests_dir, test_file=test_file)

    commands = list()

    commands.append([
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
        'up',
        '--detach',
        '--renew-anon-volumes',
        '--force-recreate',
    ])

    # Copy the whole "tests/" directory because:
    #
    # 1) Certain test files might be using other test files
    # 2) Directory might have test data made available in "tests/data/"
    #
    commands.append([
        'docker',
        'cp',
        tests_dir,
        '{}_{}_1:/'.format(project_name, container_name),
    ])

    commands.append([
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
        'exec',
        container_name,
        '/tests' + test_file[len(tests_dir):],

        # If the test has failed, the service logs might provide a clue as to why that happened, so we print them here
        '||', '{',
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
        'logs',
        ';', 'false;', '}',
    ])

    commands.append([
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
        'down',
        '--volumes',
        '--remove-orphans',
    ])

    return commands


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Print commands to run tests in a single test file.',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument('-c', '--all_containers_dir', required=True, type=str,
                        help='Directory with container subdirectories.')
    parser.add_argument('test_file', help='Perl or Python test file.')
    args = parser.parse_args()

    for command_ in docker_test_commands(all_containers_dir=args.all_containers_dir, test_file=args.test_file):
        print(' '.join(command_))
