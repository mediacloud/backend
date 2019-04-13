#!/usr/bin/env python3

import argparse
import glob
import os
import sys
from typing import List

PRINT_TEST_COMMANDS_SCRIPT_FILENAME = 'print_run_test_commands.py'
"""Script that will be called to run a single test."""


def _find_files_with_extension(directory: str, extension: str) -> List[str]:
    """
    Find all files with a given extension in a directory.

    :param directory: Directory to look into.
    :param extension: File extension.
    :return: List of files with a given extension found in a directory.
    """

    assert extension.startswith('.'), 'Extension must start with a period.'

    found_files = []
    if os.path.isdir(directory):
        for root, dirs, files in os.walk(directory):
            for f in files:
                full_path = os.path.join(root, f)
                if os.path.splitext(full_path)[1] == extension:
                    found_files.append(full_path)

    return sorted(found_files)


def docker_all_tests_commands(all_containers_dir: str) -> List[List[str]]:
    """
    Return list commands to execute in order to run all test files from all containers.

    :param all_containers_dir: Directory with container subdirectories.
    :return: List of commands (as lists) to execute in order to run all test files from all containers.
    """

    if not os.path.isdir(all_containers_dir):
        raise ValueError("Containers directory '{}' does not exist.".format(all_containers_dir))

    all_containers_dir = os.path.abspath(all_containers_dir)

    pwd = os.path.dirname(os.path.realpath(__file__))
    print_test_commands_script = os.path.join(pwd, PRINT_TEST_COMMANDS_SCRIPT_FILENAME)
    if not os.path.isfile(print_test_commands_script):
        raise ValueError("Print test commands script '{}' does not exist.".format(print_test_commands_script))
    if not os.access(print_test_commands_script, os.X_OK):
        raise ValueError("Print test commands script '{}' is not executable.".format(print_test_commands_script))

    commands = list()

    for container_path in sorted(glob.glob('{}/*'.format(all_containers_dir))):
        if os.path.isdir(container_path):

            tests_dir = os.path.join(container_path, 'tests')
            if not os.path.isdir(tests_dir):
                print("Skipping '{container_path}' as it has no '{tests_dir}' subdirectory.".format(
                    container_path=container_path,
                    tests_dir=tests_dir,
                ), file=sys.stderr)
                continue

            perl_tests_dir = os.path.join(tests_dir, 'perl')
            python_tests_dir = os.path.join(tests_dir, 'python')

            perl_tests = _find_files_with_extension(perl_tests_dir, '.t')
            python_tests = _find_files_with_extension(python_tests_dir, '.py')

            if not (perl_tests or python_tests):
                # Might be a programmer error
                raise ValueError("Tests directory '{tests_dir}' exists but no tests were found.".format(
                    tests_dir=tests_dir,
                ))

            for test_file in perl_tests + python_tests:
                commands.append([
                    print_test_commands_script,
                    '--all_containers_dir', all_containers_dir,
                    test_file,

                    # Script merely prints the commands to run so we have to pipe them to "bash" to actually run them
                    '|',
                    'bash',
                ])

    return commands


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Print commands to run all tests found in all containers.',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument('-c', '--all_containers_dir', required=True, type=str,
                        help='Directory with container subdirectories.')
    args = parser.parse_args()

    for command_ in docker_all_tests_commands(all_containers_dir=args.all_containers_dir):
        print(' '.join(command_))
