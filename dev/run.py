#!/usr/bin/env python3

"""
Set up Docker Compose environment, run a command, and then clean up said environment.

Usage:

    ./dev/run.py common bash

or:

    ./dev/run.py common -- py.test -v -s /path/to/test.py

This script can print the commands that are going to be run instead of running them itself:

    ./dev/run.py -p common bash

"""

import os
import re
import subprocess
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


def _project_name(container_name: str, command: List[str]) -> str:
    """
    Return docker-compose "project name" for a specific command.

    :param container_name: Main container's name.
    :param command: Command to run in said container.
    :return: docker-compose project name.
    """
    command = ' '.join(command)
    sanitized_command = re.sub(r'\W+', '_', command, flags=re.ASCII).lower()
    sanitized_command = sanitized_command.strip('_')

    project_name = 'mc-{}-{}'.format(container_name, sanitized_command)

    return project_name


def docker_run_commands(all_apps_dir: str, app_dirname: str, command: List[str], map_ports: bool) -> List[List[str]]:
    """
    Return a list commands to execute in order to run a command in the main container within Compose environment.

    :param all_apps_dir: Directory with container subdirectories.
    :param app_dirname: Main container's directory name.
    :param command: Command to run in the main container.
    :param map_ports: True if containers' ports should be mapped to host machine (when configured in "ports:").
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

    map_ports_args = []
    if map_ports:
        map_ports_args = ['--service-ports']

    docker_compose = [
        'docker-compose',
        '--project-name', project_name,
        '--file', docker_compose_path,
        # Enable support for "deploy:" in non-swarm mode
        '--compatibility',
    ]

    commands.append(docker_compose + ['run', '--rm'] + map_ports_args + [container_name] + command)
    commands.append(docker_compose + ['down', '--volumes'])

    return commands


class DockerRunArguments(DockerArguments):
    """
    Arguments with a container directory name and command.
    """

    def map_ports(self) -> bool:
        """
        Return True if ports configured in "ports:" should be mapped to host for all containers.
        :return: True if ports configured in "ports:" should be mapped to host for all containers.
        """
        return self._args.map_ports

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

    def args(self) -> List[str]:
        """
        Return arguments of the command to run in the main container.

        :return: Arguments of the command to run in the main container.
        """
        return self._args.args

    def concat_command_and_args(self) -> str:
        """Return concatenated command and arguments."""
        return ' '.join([self.command()] + self.args())


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
        self._parser.add_argument('-m', '--map_ports', action='store_true',
                                  help="Map containers' ports to the host machine.")
        self._parser.add_argument('app_dirname', type=str, help="Main app directory name, e.g. 'common'.")
        self._parser.add_argument('command', type=str, help="Command to run, e.g. 'bash'.")
        self._parser.add_argument('args', type=str, nargs='*', help="Arguments to the command.")

    def parse_arguments(self) -> DockerRunArguments:
        """
        Parse arguments and return an object with parsed arguments.

        :return: DockerRunArguments object.
        """
        return DockerRunArguments(self._parser.parse_args())


if __name__ == '__main__':
    parser = DockerRunArgumentParser(description='Print commands to run an arbitrary command in Compose environment.')
    args = parser.parse_arguments()

    commands_ = docker_run_commands(
        all_apps_dir=args.all_apps_dir(),
        app_dirname=args.app_dirname(),
        command=[args.command()] + args.args(),
        map_ports=args.map_ports(),
    )

    if args.print_commands():
        for command_ in commands_:
            print(' '.join(command_))

    else:

        # If command in "docker-compose run" fails, we'll store its exception here to later throw back to the user
        last_exception = None

        for command_ in commands_:
            try:
                subprocess.check_call(command_)
            except subprocess.CalledProcessError as ex_:
                last_exception = ex_

        if last_exception:
            raise last_exception
