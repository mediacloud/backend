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
* Stopping workers after running `test_workflow.py` is very slow
* Test running the same activity multiple times
* Clean up GCS bucket after running `test_workflow.py`
* If an activity throws an exception, its message should get printed out to the console as well (in addition to
  Temporal's log)
* Track failed workflows / activities in Munin
