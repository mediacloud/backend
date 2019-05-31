#!/usr/bin/env python3

"""
Print commands that will set up Compose environment, run a command, and then clean up said environment.

Usage example:

    bash <(./dev/run.py common bash)

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

    project_name = 'mc-{}-{}'.format(container_name, sanitized_command)

    return project_name


def docker_run_commands(all_apps_dir: str, app_dirname: str, command: str) -> List[List[str]]:
    """
    Return a list commands to execute in order to run a command in the main container within Compose environment.

    :param all_apps_dir: Directory with container subdirectories.
    :param app_dirname: Main container's directory name.
    :param command: Command to run in the main container.
    :return: List of commands (as lists) to execute in order to run a command.
    """
    if not os.path.isdir(all_apps_dir):
        raise ValueError("Apps directory '{}' does not exist.".format(all_apps_dir))

    all_apps_dir = os.path.abspath(all_apps_dir)

    main_container_dir = os.path.join(all_apps_dir, app_dirname)

    docker_compose_path = os.path.join(main_container_dir, DOCKER_COMPOSE_FILENAME)
    if not os.path.isfile(docker_compose_path):
        raise ValueError("docker-compose configuration was not found at '{}'.".format(docker_compose_path))

    app_dirname = Path(main_container_dir).parts[-1]
    container_name = app_dirname

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
        '--compatibility',  # Add limits from "deploy" section to non-swarm deployment
        'up',
        '--no-start',
        '--renew-anon-volumes',
        '--force-recreate',
    ])

    commands.append([
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
        '--compatibility',
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
        '--compatibility',
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

    def app_dirname(self) -> str:
        """
        Return main container's directory name.
        :return: Main container's directory name, e.g. 'common'.
        """
        return self._args.app_dirname

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
        self._parser.add_argument('app_dirname', type=str, help="Main app directory name, e.g. 'common'.")
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

    for command_ in docker_run_commands(all_apps_dir=args.all_apps_dir(),
                                        app_dirname=args.app_dirname(),
                                        command=args.command()):
        print(' '.join(command_))
