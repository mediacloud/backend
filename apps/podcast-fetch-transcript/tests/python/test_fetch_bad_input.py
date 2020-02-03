import pytest

from podcast_fetch_transcript.exceptions import McOperationNotFoundException, McMisconfiguredSpeechAPIException
from podcast_fetch_transcript.fetch import fetch_transcript


def test_fetch_transcript_invalid_id():
    """Try fetching transcript with an invalid Speech API operation ID."""
    with pytest.raises(McMisconfiguredSpeechAPIException, message="Fetch invalid transcript"):
        fetch_transcript(speech_operation_id='invalid')


def test_fetch_transcript_nonexistent_id():
    """Try fetching transcript with an nonexistent (although valid) Speech API operation ID."""
    with pytest.raises(McOperationNotFoundException, message="Fetch nonexistent transcript"):
        fetch_transcript(speech_operation_id='1234567890')