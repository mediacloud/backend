"""Utility functions for dealing with csvs."""

import csv
import io


def get_csv_string_from_dicts(dicts: list) -> str:
    """Given a list of dicts, return a representative csv string."""
    if len(dicts) < 1:
        return ''

    csvio = io.StringIO()

    csvwriter = csv.DictWriter(csvio, fieldnames=dicts[0].keys())

    csvwriter.writeheader()
    [csvwriter.writerow(d) for d in dicts]

    return csvio.getvalue()


def get_dicts_from_csv_string(csvstring: str) -> list:
    """Given a csv string, return a list of dicts."""
    if len(csvstring) < 1:
        return []

    csvio = io.StringIO(csvstring)

    return list(csv.DictReader(csvio))
