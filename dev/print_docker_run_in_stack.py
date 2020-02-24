#!/usr/bin/env python3

"""
Print 'docker run' command which joins a running stack with the right production configuration (environment variables).

Usage:

    ./dev/print_docker_run_in_stack.py ~/production-docker-config/docker-compose.yml topics-mine

"""

import argparse
import shlex
import sys
from typing import List

from utils import load_validate_docker_compose_yaml, InvalidDockerComposeYMLException


def run_in_stack_command(
        production_docker_compose_file: str,
        service_name: str,
        command: str,
        stack_name: str,
) -> List[str]:
    """
    Generate 'docker run' command which joins a running production stack and exports production's environment variables.

    :param production_docker_compose_file: Path to production's docker-compose.yml
    :param service_name: Service name to read the image name and environment variables from, e.g. "topics-mine".
    :param command: Command to run in a newly started container.
    :param stack_name: Name of a Docker stack to join.
    :return: List of command parts in subprocess.check_call() syntax, i.e. ['docker', 'run', ...]
    """
    docker_compose_contents = load_validate_docker_compose_yaml(production_docker_compose_file)

    networks = docker_compose_contents['networks']
    if len(networks) != 1:
        raise InvalidDockerComposeYMLException("I've expected to find a single network only.")

    network_name = list(networks.keys())[0]
    assert network_name

    docker_run_command = [
        'docker',
        'run',
        '-it',
        '--network', '{}_{}'.format(stack_name, network_name),
    ]

    service = docker_compose_contents['services'].get(service_name, None)
    if not service:
        raise InvalidDockerComposeYMLException(
            "Service '{}' was not found in '{}.".format(service_name, production_docker_compose_file)
        )

    service_env = service.get('environment', {})
    if service_env:

        if not isinstance(service_env, dict):
            raise InvalidDockerComposeYMLException(
                "Service's '{}' environment variables are not a dictionary".format(service_name)
            )

        for env_key, env_value in service_env.items():
            docker_run_command.extend([
                '-e',
                '{}={}'.format(env_key, shlex.quote(env_value)),
            ])

    service_image = service.get('image', None)
    if not service_image:
        raise InvalidDockerComposeYMLException("Image is unset for service '{}'.".format(service_name))

    docker_run_command.extend([
        service_image,
        command,
    ])

    return docker_run_command


def _print_warning_message(message: str) -> None:
    """
    Print a colored warning message to STDERR.
    :param message: Message to print.
    """
    color_start = '\033[93m'
    color_end = '\033[0m'
    print("{}{}{}".format(color_start, message, color_end), file=sys.stderr)
    sys.stderr.flush()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description="Print 'docker run' command to run a new container in a Docker stack.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument('-n', '--stack_name', type=str, required=False, default='mediacloud',
                        help='Docker stack name (from `docker stack deploy <...>`)')
    parser.add_argument('-c', '--command', type=str, required=False, default='bash',
                        help='Command to run in a newly started container')
    parser.add_argument('production_docker_compose_file', type=str,
                        help='Path to production docker-compose.yml')
    parser.add_argument('service_name', type=str,
                        help='Service to use for image name and environment variables')

    args = parser.parse_args()

    if not args.production_docker_compose_file.endswith('.yml'):
        raise ValueError(
            "Filename '{}' doesn't look like a YAML file to me.".format(args.production_docker_compose_file)
        )

    if '.dist.' in args.production_docker_compose_file:
        raise ValueError(
            "Filename '{}' doesn't look like a *production* docker-compose.yml to me.".format(
                args.production_docker_compose_file
            )
        )

    command_ = run_in_stack_command(
        production_docker_compose_file=args.production_docker_compose_file,
        service_name=args.service_name,
        command=args.command,
        stack_name=args.stack_name,
    )

    _print_warning_message("""
Here's a "docker run" command that will:

* Start a new container using "{service_name}" service's image and environment variables;
* Make the container join "{stack_name}" Docker stack;
* Run "{command}" in said container:
    """.format(
        service_name=args.service_name,
        stack_name=args.stack_name,
        command=args.command,
    ))

    # Add one extra space so that the command with secrets doesn't get stored in shell history
    print(' ' + (' '.join(command_)))

    _print_warning_message("""
Make sure to:

* Preserve a single whitespace in front of the command so that the command doesn't get logged in shell history;
* Verify that you're starting a container using a correct image tag, e.g. "release".  
""")
