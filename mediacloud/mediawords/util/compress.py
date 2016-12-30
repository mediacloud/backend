import os

from mediawords.util.log import create_logger
from mediawords.util.paths import file_extension
from mediawords.util.process import run_command_in_foreground, McRunCommandInForegroundException

l = create_logger(__name__)


class McExtractTarballToDirectoryException(Exception):
    pass


def extract_tarball_to_directory(archive_file: str, dest_directory: str, strip_root: bool = False) -> None:
    """Extract Tar archive (.tar, .tar.gz or .tgz) to destination directory, optionally stripping the root directory
    first."""

    if not os.path.isfile(archive_file):
        raise McExtractTarballToDirectoryException("Archive at '%s' does not exist" % archive_file)

    archive_file_extension = file_extension(archive_file)
    if archive_file_extension in [".gz", ".tgz"]:
        tar_args = "-zxf"
    elif archive_file_extension in [".tar"]:
        tar_args = "-xf"
    else:
        raise McExtractTarballToDirectoryException("Unsupported archive '%s' with extension '%s'" %
                                                   (archive_file, archive_file_extension))

    args = ["tar",
            tar_args, archive_file,
            "-C", dest_directory]
    if strip_root:
        args += ['--strip', '1']

    try:
        run_command_in_foreground(args)
    except McRunCommandInForegroundException as ex:
        raise McExtractTarballToDirectoryException("Error while extracting archive '%s': %s" % (archive_file, str(ex)))


class McExtractZipToDirectoryException(Exception):
    pass


def extract_zip_to_directory(archive_file: str, dest_directory: str) -> None:
    """Extract ZIP archive (.zip or .war) to destination directory."""

    if not os.path.isfile(archive_file):
        raise McExtractZipToDirectoryException("Archive at '%s' does not exist" % archive_file)

    archive_file_extension = file_extension(archive_file)
    if archive_file_extension not in [".zip", ".war"]:
        raise McExtractZipToDirectoryException(
            "Unsupported archive '%s' with extension '%s'" % (archive_file, archive_file_extension))

    args = ["unzip", "-q", archive_file, "-d", dest_directory]

    try:
        run_command_in_foreground(args)
    except McRunCommandInForegroundException as ex:
        raise McExtractZipToDirectoryException("Error while extracting archive '%s': %s" % (archive_file, str(ex)))
