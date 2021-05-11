# Podcast transcription

## TODO

* [Upload transcriptions directly to GCS](https://cloud.google.com/speech-to-text/docs/async-recognize#speech_transcribe_async_gcs-python)
  once that's no longer a demo feature
* Add all Chinese variants to `alternative_language_codes`
* Add all Mexican Spanish variants to `alternative_language_codes`
* Post-init [validation of dataclasses](https://docs.python.org/3/library/dataclasses.html#post-init-processing)
* When operation ID can't be found, resubmit the podcast for transcription as that might mean that the operation results
  weren't fetched in time and so the operation has expired
* Add heartbeats to transcoding activity
* Consider making `MAX_ENCLOSURE_SIZE` and `MAX_DURATION` configurable via environment variables