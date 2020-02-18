import pytest

from podcast_poll_due_operations.due_operations import poll_for_due_operations, AbstractFetchTranscriptQueue
from podcast_poll_due_operations.exceptions import McJobBrokerErrorException

from .setup_due_operation import SetupTestOperation


class MockFailingFetchTranscriptQueue(AbstractFetchTranscriptQueue):

    def add_to_queue(self, podcast_episode_transcript_fetches_id: int) -> None:
        raise Exception("Job broker is down")


class TestFailingJobBroker(SetupTestOperation):

    def test_failing_job_broker(self):
        """Test what happens if the job broker fails."""

        fetch_transcript_queue = MockFailingFetchTranscriptQueue()

        with pytest.raises(McJobBrokerErrorException):
            poll_for_due_operations(
                fetch_transcript_queue=fetch_transcript_queue,
                stop_after_first_empty_chunk=True,
            )

        all_fetches = self.db.select(
            table='podcast_episode_transcript_fetches',
            what_to_select='*',
        ).hashes()

        assert len(all_fetches) == 1, "The fetch should have been kept in the table."
        fetch = all_fetches[0]

        assert not fetch['added_to_queue_at'], "Timestamp for when the fetch as added to the queue should be empty."
