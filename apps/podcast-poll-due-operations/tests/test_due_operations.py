from podcast_poll_due_operations.due_operations import poll_for_due_operations, AbstractFetchTranscriptionQueue

from .setup_due_operation import SetupTestOperation


class MockCounterFetchTranscriptionQueue(AbstractFetchTranscriptionQueue):
    __slots__ = [
        'story_count',
    ]

    def __init__(self):
        self.story_count = 0

    def add_to_queue(self, stories_id: int, speech_operation_id: str) -> None:
        self.story_count += 1


class TestPollForDueOperations(SetupTestOperation):

    def test_poll_for_due_operations(self):
        """Simple test."""

        fetch_transcription_queue = MockCounterFetchTranscriptionQueue()

        poll_for_due_operations(
            stop_after_first_empty_chunk=True,
            fetch_transcription_queue=fetch_transcription_queue,
        )

        assert len(self.db.select(
            table='podcast_episode_operations',
            what_to_select='*',
        ).hashes()) == 0, "All operations should have been added to the queue."
        assert fetch_transcription_queue.story_count == 1, "A single story should have been added to the fetch queue."
