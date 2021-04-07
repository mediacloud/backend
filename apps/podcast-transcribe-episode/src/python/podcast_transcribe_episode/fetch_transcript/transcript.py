import dataclasses
from typing import List


@dataclasses.dataclass
class UtteranceAlternative(object):
    """One of the alternatives of what might have been said in an utterance."""

    text: str
    """Utterance text."""

    confidence: float
    """How confident Speech API is that it got it right."""


@dataclasses.dataclass
class Utterance(object):
    """A single transcribed utterance (often but not always a single sentence)."""

    alternatives: List[UtteranceAlternative]
    """Alternatives of what might have been said in an utterance, ordered from the best to the worst guess."""

    bcp47_language_code: str
    """BCP 47 language code; might be different from what we've passed as the input."""

    @property
    def best_alternative(self) -> UtteranceAlternative:
        """Return best alternative for what might have been said in an utterance."""
        return self.alternatives[0]


@dataclasses.dataclass
class Transcript(object):
    """A single transcript."""

    stories_id: int
    """Story ID."""

    utterances: List[Utterance]
    """List of ordered utterances in a transcript."""
