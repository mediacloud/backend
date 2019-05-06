#!/usr/bin/env python3

"""
Print commands that will set up Compose environment, run a command, and then clean up said environment.

Usage example:

    bash <(./build_tools/print_run_commands.py common bash)

"""

import os
import re
from pathlib import Path
from typing import List

# Given that docker-compose is present, we assume that PyYAML is installed

from utils import DockerArgumentParser, DockerArguments

try:
    from yaml import safe_load as load_yaml
except ModuleNotFoundError:
    raise ImportError("Please install PyYAML.")

DOCKER_COMPOSE_FILENAME = 'docker-compose.tests.yml'
"""Filename of 'docker-compose.yml' used for development and running tests."""


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


def _project_name(container_name: str, command: str) -> str:
    """
    Return docker-compose "project name" for a specific command.

    :param container_name: Main container's name.
    :param command: Command to run in said container.
    :return: docker-compose project name.
    """
    sanitized_command = re.sub(r'\W+', '_', command, flags=re.ASCII).lower()
    sanitized_command = sanitized_command.strip('_')

    project_name = '{}-{}'.format(container_name, sanitized_command)

    return project_name


def docker_run_commands(all_containers_dir: str, container_dirname: str, command: str) -> List[List[str]]:
    """
    Return a list commands to execute in order to run a command in the main container within Compose environment.

    :param all_containers_dir: Directory with container subdirectories.
    :param container_dirname: Main container's directory name.
    :param command: Command to run in the main container.
    :return: List of commands (as lists) to execute in order to run a command.
    """
    if not os.path.isdir(all_containers_dir):
        raise ValueError("Containers directory '{}' does not exist.".format(all_containers_dir))

    all_containers_dir = os.path.abspath(all_containers_dir)

    main_container_dir = os.path.join(all_containers_dir, container_dirname)

    docker_compose_path = os.path.join(main_container_dir, DOCKER_COMPOSE_FILENAME)
    if not os.path.isfile(docker_compose_path):
        raise ValueError("docker-compose configuration was not found at '{}'.".format(docker_compose_path))

    container_dirname = Path(main_container_dir).parts[-1]
    container_name = "mc_" + container_dirname.replace('-', '_')

    try:
        _validate_docker_compose_yml(docker_compose_path=docker_compose_path, container_name=container_name)
    except InvalidDockerComposeYMLException as ex:
        raise ValueError("docker-compose configuration in '{}' is invalid: {}".format(docker_compose_path, ex))

    project_name = _project_name(container_name=container_name, command=command)

    commands = list()

    commands.append([
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
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
        'run',
        container_name,
        command,
    ])

    # Store exit code to later send back to the caller
    commands.append([
        'CONTAINER_EXIT_CODE=$?',
    ])

    commands.append([
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
        'down',
        '--volumes',
    ])

    # Send back main container's exit code to the caller
    commands.append([
        'exit', '$CONTAINER_EXIT_CODE',
    ])

    return commands


class DockerRunArguments(DockerArguments):
    """
    Arguments with a container directory name and command.
    """

    def container_dirname(self) -> str:
        """
        Return main container's directory name.
        :return: Main container's directory name, e.g. 'common'.
        """
        return self._args.container_dirname

    def command(self) -> str:
        """
        Return command to run in the main container.

        :return: Command to run in the main container.
        """
        return self._args.command


class DockerRunArgumentParser(DockerArgumentParser):
    """
    Argument parser that includes a command to run.
    """

    def __init__(self, description: str):
        """
        Constructor.

        :param description: Description of the script to print when "--help" is passed.
        """
        super().__init__(description=description)
        self._parser.add_argument('container_dirname', type=str, help="Main container directory name, e.g. 'common'.")
        self._parser.add_argument('command', type=str, help="Command to run, e.g. '/bin/bash'.")

    def parse_arguments(self) -> DockerRunArguments:
        """
        Parse arguments and return an object with parsed arguments.

        :return: DockerRunArguments object.
        """
        return DockerRunArguments(self._parser.parse_args())


if __name__ == '__main__':
    parser = DockerRunArgumentParser(description='Print commands to run an arbitrary command in Compose environment.')
    args = parser.parse_arguments()

    for command_ in docker_run_commands(all_containers_dir=args.all_containers_dir(),
                                        container_dirname=args.container_dirname(),
                                        command=args.command()):
        print(' '.join(command_))
