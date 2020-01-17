import abc
import time

from mediawords.db import connect_to_db
from mediawords.util.log import create_logger

from podcast_poll_due_operations.exceptions import McJobBrokerErrorException

log = create_logger(__name__)


class AbstractFetchTranscriptQueue(object, metaclass=abc.ABCMeta):
    """
    Abstract class for adding a story ID to the "podcast-fetch-transcript" queue.

    Useful for testing as having such a class can help us find out whether stories get added to the actual job queue.
    """

    @abc.abstractmethod
    def add_to_queue(self, stories_id: int, speech_operation_id: str) -> None:
        """
        Add story ID to "podcast-fetch-transcript" job queue.

        :param stories_id: Story ID to add to the queue.
        :param speech_operation_id: Speech API operation ID.
        """
        raise NotImplemented("Abstract method")


def poll_for_due_operations(fetch_transcript_queue: AbstractFetchTranscriptQueue,
                            stop_after_first_empty_chunk: bool = False,
                            wait_after_empty_poll: int = 30,
                            stories_chunk_size: int = 100) -> None:
    """
    Continuously poll for due operations, add such operations to "podcast-fetch-transcript" queue.

    Never returns, unless 'stop_after_first_empty_chunk' is set.

    :param fetch_transcript_queue: Queue helper object to use for adding a story ID to "podcast-fetch-transcript"
                                      queue (useful for testing).
    :param stop_after_first_empty_chunk: If True, stop after the first attempt to fetch a chunk of due story IDs comes
                                         out empty (useful for testing).
    :param wait_after_empty_poll: Seconds to wait after there were no due story IDs found.
    :param stories_chunk_size: Max. due story IDs to fetch in one go; the chunk will be deleted + returned in a
                               transaction, which will get reverted if RabbitMQ fails, so we don't want to
                               hold that transaction for too long.
    """

    if not fetch_transcript_queue:
        raise McJobBrokerErrorException(f"Fetch transcript queue object is unset.")

    while True:

        db = connect_to_db()

        db.begin()

        log.info("Polling...")
        due_operations = db.query("""
            DELETE FROM podcast_episode_operations
            WHERE stories_id IN (
                SELECT stories_id
                FROM podcast_episode_operations
                WHERE fetch_results_at <= NOW()

                -- Get the oldest operations first
                ORDER BY fetch_results_at

                -- Don't fetch too much of stories at once
                LIMIT %(stories_chunk_size)s
            )

            RETURNING stories_id, speech_operation_id
        """, {
            'stories_chunk_size': stories_chunk_size,
        }).hashes()

        if due_operations:

            try:
                log.info(f"Adding {len(due_operations)} due operations to the transcription fetch queue...")

                for operation in due_operations:
                    log.debug((
                        f"Adding story {operation['stories_id']} (operation {operation['speech_operation_id']}) "
                        "to the transcription fetch queue..."
                    ))
                    fetch_transcript_queue.add_to_queue(
                        stories_id=operation['stories_id'],
                        speech_operation_id=operation['speech_operation_id'],
                    )

                log.info(f"Done adding {len(due_operations)} due operations to the transcription fetch queue")
            except Exception as ex:
                db.rollback()

                raise McJobBrokerErrorException(f"Unable to add one or more stories the the job queue: {ex}")

            db.commit()

        else:

            db.commit()

            if stop_after_first_empty_chunk:
                log.info(f"No due story IDs found, stopping...")
                break
            else:
                log.info(f"No due story IDs found, waiting for {wait_after_empty_poll} seconds...")
                time.sleep(wait_after_empty_poll)
