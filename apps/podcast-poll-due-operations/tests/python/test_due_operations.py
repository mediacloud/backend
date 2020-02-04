from podcast_poll_due_operations.due_operations import poll_for_due_operations, AbstractFetchTranscriptQueue

from .setup_due_operation import SetupTestOperation


class MockCounterFetchTranscriptQueue(AbstractFetchTranscriptQueue):
    __slots__ = [
        'story_count',
    ]

    def __init__(self):
        self.story_count = 0

    def add_to_queue(self, podcast_episode_transcript_fetches_id: int) -> None:
        self.story_count += 1


class TestPollForDueOperations(SetupTestOperation):

    def test_poll_for_due_operations(self):
        """Simple test."""

        fetch_transcript_queue = MockCounterFetchTranscriptQueue()

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

        assert fetch['added_to_queue_at'], "Timestamp for when the fetch as added to the queue should be set."

        assert fetch_transcript_queue.story_count == 1, "A single story should have been added to the fetch queue."
