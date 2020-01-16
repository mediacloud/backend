#!/usr/bin/env python3

from mediawords.util.process import fatal_error

from podcast_poll_due_operations.due_operations import poll_for_due_operations

if __name__ == '__main__':
    try:
        poll_for_due_operations()
    except Exception as ex:
        # Hard and unknown errors (no soft errors here)
        fatal_error(f"Unable to poll for due operations: {ex}")
