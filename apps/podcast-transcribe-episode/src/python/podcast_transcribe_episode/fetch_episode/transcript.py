import abc
import dataclasses
from typing import List, Dict, Any


class _AbstractFromDict(object, metaclass=abc.ABCMeta):

    @classmethod
    @abc.abstractmethod
    def from_dict(cls, input_dict: Dict[str, Any]) -> '_AbstractFromDict':
        raise NotImplementedError


@dataclasses.dataclass
class UtteranceAlternative(object):
    """One of the alternatives of what might have been said in an utterance."""

    text: str
    """Utterance text."""

    confidence: float
    """How confident Speech API is that it got it right."""

    @classmethod
    def from_dict(cls, input_dict: Dict[str, Any]) -> 'UtteranceAlternative':
        return cls(
            text=input_dict['text'],
            confidence=input_dict['confidence'],
        )


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

    @classmethod
    def from_dict(cls, input_dict: Dict[str, Any]) -> 'Utterance':
        raise cls(
            alternatives=[UtteranceAlternative.from_dict(x) for x in input_dict['alternatives']],
            bcp47_language_code=input_dict['bcp47_language_code'],
        )


@dataclasses.dataclass
class Transcript(object):
    """A single transcript."""

    utterances: List[Utterance]
    """List of ordered utterances in a transcript."""

    # Only Transcript is to be serialized to JSON so to_dict() is implemented only here
    def to_dict(self) -> Dict[str, Any]:
        return dataclasses.asdict(self)

    @classmethod
    def from_dict(cls, input_dict: Dict[str, Any]) -> 'Transcript':
        return cls(utterances=[Utterance.from_dict(x) for x in input_dict['utterances']])
