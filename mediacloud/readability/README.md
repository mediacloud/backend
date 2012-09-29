nltk_contrib Readability Library Modifications
==============================================

This contains a few hacks to make the readability nltk_contrib library actually work:

- In `textanalyzer.py`, I have commented out the printouts of the computed sums, and the
warning that it couldn't detect the language.
- In `languageclassifier.py`, I made the loading of the `lang_data.pickle` load from 
the correct directory.
