#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, JobBrokerApp
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error
from mediawords.util.similarweb.media import (
    update_estimated_visits_for_media_id,
    McUpdateEstimatedVisitsForMediaIDFatalException,
)

log = create_logger(__name__)


class UpdateEstimatedVisits(AbstractJob):
    """

    Update estimated visits for media ID.

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/similarweb/update_estimated_visits.py

    """

    @classmethod
    def run_job(cls, media_id: int) -> None:
        if isinstance(media_id, bytes):
            media_id = decode_object_from_bytes_if_needed(media_id)

        media_id = int(media_id)

        db = connect_to_db()

        try:
            update_estimated_visits_for_media_id(db=db, media_id=media_id)
        except McUpdateEstimatedVisitsForMediaIDFatalException as ex:
            # Stop operation on fatal exceptions
            fatal_error(f"Fatal exception while processing media {media_id}: {ex}")

    @classmethod
    def queue_name(cls) -> str:
        return 'MediaWords::Job::SimilarWeb::UpdateEstimatedVisits'


if __name__ == '__main__':
    app = JobBrokerApp(job_class=UpdateEstimatedVisits)
    app.start_worker()
