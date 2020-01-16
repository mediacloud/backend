import pytest

from podcast_poll_due_operations.due_operations import poll_for_due_operations, AbstractFetchTranscriptionQueue
from podcast_poll_due_operations.exceptions import McJobBrokerErrorException

from .setup_due_operation import SetupTestOperation


class MockFailingFetchTranscriptionQueue(AbstractFetchTranscriptionQueue):

    def add_to_queue(self, stories_id: int, speech_operation_id: str) -> None:
        raise Exception("Job broker is down")


class TestFailingJobBroker(SetupTestOperation):

    def test_failing_job_broker(self):
        """Test what happens if the job broker fails."""

        fetch_transcription_queue = MockFailingFetchTranscriptionQueue()

        with pytest.raises(McJobBrokerErrorException):
            poll_for_due_operations(
                stop_after_first_empty_chunk=True,
                fetch_transcription_queue=fetch_transcription_queue,
            )

        assert len(self.db.select(
            table='podcast_episode_operations',
            what_to_select='*',
        ).hashes()) == 1, "Operation is still in the table."
