#!/usr/bin/env python3

from mediawords.job import JobBroker
from mediawords.util.process import fatal_error

from podcast_poll_due_operations.due_operations import poll_for_due_operations, AbstractFetchTranscriptQueue


class JobBrokerFetchTranscriptQueue(AbstractFetchTranscriptQueue):
    """Add fetch transcript jobs to job broker's queue."""

    def add_to_queue(self, stories_id: int, speech_operation_id: str) -> None:
        JobBroker(queue_name='MediaWords::Job::Podcast::FetchTranscript').add_to_queue(
            stories_id=stories_id,
            speech_operation_id=speech_operation_id,
        )


if __name__ == '__main__':
    try:
        fetch_transcript_queue = JobBrokerFetchTranscriptQueue()
        poll_for_due_operations(fetch_transcript_queue=fetch_transcript_queue)
    except Exception as ex:
        # Hard and unknown errors (no soft errors here)
        fatal_error(f"Unable to poll for due operations: {ex}")
