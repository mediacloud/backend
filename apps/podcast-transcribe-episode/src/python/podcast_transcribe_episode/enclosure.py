import dataclasses
from typing import Optional, Dict, Any

# noinspection PyPackageRequirements
from furl import furl

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.url import is_http_url

log = create_logger(__name__)

StoryEnclosureDict = Dict[str, Any]


@dataclasses.dataclass
class StoryEnclosure(object):
    """Single story enclosure derived from feed's <enclosure /> element."""

    __MP3_MIME_TYPES = {'audio/mpeg', 'audio/mpeg3', 'audio/mp3', 'audio/x-mpeg-3'}
    """MIME types which MP3 files might have."""

    story_enclosures_id: int
    """ID from 'story_enclosures' table."""

    url: str
    """Enclosure's URL, e.g. 'https://www.example.com/episode.mp3'."""

    mime_type: Optional[str]
    """Enclosure's reported MIME type, or None if it wasn't reported; e.g. 'audio/mpeg'."""

    length: Optional[int]
    """Enclosure's reported length in bytes, or None if it wasn't reported."""

    def mime_type_is_mp3(self) -> bool:
        """Return True if declared MIME type is one of the MP3 ones."""
        if self.mime_type:
            if self.mime_type.lower() in self.__MP3_MIME_TYPES:
                return True
        return False

    def mime_type_is_audio(self) -> bool:
        """Return True if declared MIME type is an audio type."""
        if self.mime_type:
            if self.mime_type.lower().startswith('audio/'):
                return True
        return False

    def mime_type_is_video(self) -> bool:
        """Return True if declared MIME type is a video type."""
        if self.mime_type:
            if self.mime_type.lower().startswith('video/'):
                return True
        return False

    def url_path_has_mp3_extension(self) -> bool:
        """Return True if URL's path has .mp3 extension."""
        if is_http_url(self.url):
            uri = furl(self.url)
            if '.mp3' in str(uri.path).lower():
                return True
        return False

    @classmethod
    def from_db_row(cls, db_row: Dict[str, Any]) -> 'StoryEnclosure':
        return cls(
            story_enclosures_id=db_row['story_enclosures_id'],
            url=db_row['url'],
            mime_type=db_row['mime_type'],
            length=db_row['length'],
        )

    def to_dict(self) -> StoryEnclosureDict:
        return dataclasses.asdict(self)

    @classmethod
    def from_dict(cls, input_dict: StoryEnclosureDict) -> 'StoryEnclosure':
        return cls(**input_dict)


def viable_story_enclosure(db: DatabaseHandler, stories_id: int) -> Optional[StoryEnclosure]:
    """Fetch all enclosures, find and return the one that looks like a podcast episode the most (or None)."""
    story_enclosures_dicts = db.query("""
        SELECT *
        FROM story_enclosures
        WHERE stories_id = %(stories_id)s

        -- Returning by insertion order so the enclosures listed earlier will have a better chance of being considered
        -- episodes  
        ORDER BY story_enclosures_id
    """, {
        'stories_id': stories_id,
    }).hashes()

    if not story_enclosures_dicts:
        log.warning(f"Story {stories_id} has no enclosures to choose from.")
        return None

    story_enclosures = []

    for enclosure_dict in story_enclosures_dicts:
        if is_http_url(enclosure_dict['url']):
            story_enclosures.append(StoryEnclosure.from_db_row(enclosure_dict))

    chosen_enclosure = None

    # Look for MP3 files in MIME type
    for enclosure in story_enclosures:
        if enclosure.mime_type_is_mp3():
            log.info(f"Choosing enclosure '{enclosure}' due to its MP3 MIME type '{enclosure.mime_type}'")
            chosen_enclosure = enclosure
            break

    # If that didn't work, look into URL's path
    if not chosen_enclosure:
        for enclosure in story_enclosures:
            if enclosure.url_path_has_mp3_extension():
                log.info(f"Choosing enclosure '{enclosure}' due to its URL '{enclosure.url}'")
                chosen_enclosure = enclosure
                break

    # If there are no MP3s in sight, try to find any kind of audio enclosure because it's a smaller download than video
    # and faster to transcode
    if not chosen_enclosure:
        for enclosure in story_enclosures:
            if enclosure.mime_type_is_audio():
                log.info(f"Choosing enclosure '{enclosure}' due to its audio MIME type '{enclosure.mime_type}'")
                chosen_enclosure = enclosure
                break

    # In case there are no audio enclosures, look for videos then
    if not chosen_enclosure:
        for enclosure in story_enclosures:
            if enclosure.mime_type_is_video():
                log.info(f"Choosing enclosure '{enclosure}' due to its video MIME type '{enclosure.mime_type}'")
                chosen_enclosure = enclosure
                break

    # Return either the best option that we've found so far, or None if there were no (explicitly declared)
    # audio / video enclosures
    return chosen_enclosure
