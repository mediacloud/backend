#!/usr/bin/env python3

import glob
import os
import re
import sys
from typing import List, Pattern

from utils import DockerArgumentParser

RUN_TEST_SCRIPT_FILENAME = 'run_test.py'
"""Script that will be called to run a single test."""


def _find_files_with_pattern(directory: str, filename_pattern: Pattern) -> List[str]:
    """
    Find all files that match a certain pattern in a directory.

    :param directory: Directory to look into.
    :param filename_pattern: Regex pattern that the filename should match.
    :return: List of files with a given extension found in a directory.
    """

    found_files = []
    if os.path.isdir(directory):
        for root, dirs, files in os.walk(directory):
            for f in files:
                if re.match(pattern=filename_pattern, string=os.path.basename(f)):
                    full_path = os.path.join(root, f)
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
    run_test_script = os.path.join(pwd, RUN_TEST_SCRIPT_FILENAME)
    if not os.path.isfile(run_test_script):
        raise ValueError("Print test commands script '{}' does not exist.".format(run_test_script))
    if not os.access(run_test_script, os.X_OK):
        raise ValueError("Print test commands script '{}' is not executable.".format(run_test_script))

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

            perl_tests = _find_files_with_pattern(perl_tests_dir, re.compile(r'^.+?\.t$'))
            python_tests = _find_files_with_pattern(python_tests_dir, re.compile(r'^test_.+?\.py$'))

            if not (perl_tests or python_tests):
                # Might be a programmer error
                raise ValueError("Tests directory '{tests_dir}' exists but no tests were found.".format(
                    tests_dir=tests_dir,
                ))

            for test_file in perl_tests + python_tests:
                commands.append([
                    run_test_script,
                    '--all_containers_dir', all_containers_dir,
                    test_file,
                ])

    return commands


if __name__ == '__main__':
    parser = DockerArgumentParser(description='Print commands to run all tests found in all containers.')
    args = parser.parse_arguments()

    for command_ in docker_all_tests_commands(all_containers_dir=args.all_containers_dir()):
        print('bash <(' + ' '.join(command_) + ')')
