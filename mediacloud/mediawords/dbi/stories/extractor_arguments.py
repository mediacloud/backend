from mediawords.util.perl import decode_object_from_bytes_if_needed


class ExtractorArguments(object):
    """Arguments to process_extracted_story() that define how story is to be extracted."""

    # MC_REWRITE_TO_PYTHON: remake into data class / properties after Python rewrite
    __slots__ = [
        '__no_dedup_sentences',
        '__no_delete',
        '__no_tag_extractor_version',
        '__use_cache',
        '__use_existing',
    ]

    def __init__(self,
                 no_dedup_sentences: bool = False,
                 no_delete: bool = False,
                 no_tag_extractor_version: bool = False,
                 use_cache: bool = False,
                 use_existing: bool = False):
        """Constructor."""

        if isinstance(no_dedup_sentences, bytes):
            no_dedup_sentences = decode_object_from_bytes_if_needed(no_dedup_sentences)
        if isinstance(no_delete, bytes):
            no_delete = decode_object_from_bytes_if_needed(no_delete)
        if isinstance(no_tag_extractor_version, bytes):
            no_tag_extractor_version = decode_object_from_bytes_if_needed(no_tag_extractor_version)
        if isinstance(use_cache, bytes):
            use_cache = decode_object_from_bytes_if_needed(use_cache)
        if isinstance(use_existing, bytes):
            use_existing = decode_object_from_bytes_if_needed(use_existing)

        # MC_REWRITE_TO_PYTHON: remove weird casts after Python rewrite
        no_dedup_sentences = bool(int(no_dedup_sentences))
        no_delete = bool(int(no_delete))
        no_tag_extractor_version = bool(int(no_tag_extractor_version))
        use_cache = bool(int(use_cache))
        use_existing = bool(int(use_existing))

        self.__no_dedup_sentences = no_dedup_sentences
        self.__no_delete = no_delete
        self.__no_tag_extractor_version = no_tag_extractor_version
        self.__use_cache = use_cache
        self.__use_existing = use_existing

    def no_dedup_sentences(self) -> bool:
        """Return True if sentences don't have to be deduplicated."""
        return self.__no_dedup_sentences

    def no_delete(self) -> bool:
        """Return True if old sentences don't have to be deleted before inserting new ones."""
        return self.__no_delete

    def no_tag_extractor_version(self) -> bool:
        """Return True if tagging story with extractor's version is to be skipped."""
        return self.__no_tag_extractor_version

    def use_cache(self) -> bool:
        """Return True if the extractor should return a cached extractor result (if one is present in cache)."""
        return self.__use_cache

    def use_existing(self) -> bool:
        """Return True if extraction is to be skipped if the extracted text already exists in "download_texts"."""
        return self.__use_existing
