#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, JobBrokerApp
from mediawords.similarweb import get_similarweb_client
from mediawords.similarweb.tasks import update
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class SimilarWebUpdateAudienceDataJob(AbstractJob):
    """

    Create / update audience data using SimilarWeb

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/similarweb/update_audience_data.py

    """

    @classmethod
    def run_job(cls, media_id: int) -> None:
        if isinstance(media_id, bytes):
            media_id = decode_object_from_bytes_if_needed(media_id)

        media_id = int(media_id)

        db = connect_to_db()
        similarweb_client = get_similarweb_client()

        log.info("Collecting audience data for media ID {}...".format(media_id))
        update(db, media_id, similarweb_client)

        log.info("Finished collecting audience data for media ID {}".format(media_id))

    @classmethod
    def queue_name(cls) -> str:
        return 'MediaWords::Job::SimilarWeb::UpdateAudienceData'


if __name__ == '__main__':
    app = JobBrokerApp(job_class=SimilarWebUpdateAudienceDataJob)
    app.start_worker()
