#!/usr/bin/env python3

"""
Run all Perl / Python tests in their own isolated Docker Compose environments.

Usage:

    ./dev/run_all_tests.py

This script can print the commands that are going to be run instead of running them itself:

    ./dev/run_all_tests.py -p | grep common

Given that every test will be run in its own isolated environment, test runs can be parallelized to some extent, e.g. by
using "parallel" utility:

    ./dev/run_all_tests.py -p | parallel --group

"""

import glob
import os
import re
import shlex
import subprocess
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


def docker_all_tests_commands(all_apps_dir: str) -> List[List[str]]:
    """
    Return list commands to execute in order to run all test files from all apps.

    :param all_apps_dir: Directory with container subdirectories.
    :return: List of commands (as lists) to execute in order to run all test files from all apps.
    """

    if not os.path.isdir(all_apps_dir):
        raise ValueError("Apps directory '{}' does not exist.".format(all_apps_dir))

    all_apps_dir = os.path.abspath(all_apps_dir)

    pwd = os.path.dirname(os.path.realpath(__file__))
    run_test_script = os.path.join(pwd, RUN_TEST_SCRIPT_FILENAME)
    if not os.path.isfile(run_test_script):
        raise ValueError("Print test commands script '{}' does not exist.".format(run_test_script))
    if not os.access(run_test_script, os.X_OK):
        raise ValueError("Print test commands script '{}' is not executable.".format(run_test_script))

    commands = list()

    for container_path in sorted(glob.glob('{}/*'.format(all_apps_dir))):
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
                    '--all_apps_dir', all_apps_dir,
                    test_file,
                ])

    return commands


if __name__ == '__main__':
    parser = DockerArgumentParser(description='Print commands to run all tests found in all apps.')
    args = parser.parse_arguments()

    commands_ = docker_all_tests_commands(all_apps_dir=args.all_apps_dir())

    if args.print_commands():
        for command_ in commands_:
            print(' '.join([shlex.quote(c) for c in command_]))

    else:
        # Run all tests, don't stop at a single failure, raise exception if at least one of the tests failed
        last_exception = None

        for command_ in commands_:
            try:
                subprocess.check_call(command_)
            except subprocess.CalledProcessError as ex_:
                last_exception = ex_

        if last_exception:
            raise last_exception
