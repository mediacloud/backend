Date Guess Threshold Validation
========================

This document describes a short validation process to decide whether to keep the behavior in GuessDate that
only uses a guessed date if it is within some number of days of the linking story.

Problem
-------

In early tests, requiring that a date be within 60 days of the linking story of a spidered story increased accuracy.
But we are increasingly running longer, larger topics and encountered a relatively large number of badly misdated
stories that were the result of the date guess threshold disallowing what should have been an accurate
date guess.

Metric
------

The validation method is to determine of the stories with a source_link date guess method (the fallback method),
how many date guesses would be improved by removing the threshold.  We use stories within the big 2016 election topic,
which is the worst case for using the date threshold but is a critical topic for us to get right and is also the way
much of our work is moving (toward bigger, longer topics).

Method
------

I generated a random sample of stories with the source_link date guess method in the election topic, ran a script
to generate a csv with both the current source_link date and the result of the date guess if the threshold were
not applied.  I coded a random 54 stories from the resulting csv for whether the existing, guessed, or neither date
would be better (or whether a date was not applicable for that story).

Results
-------

The results indicate that removing the threshold test would significantly improve date guessing accuracy.

From the 54 code stories, here are the proportions of codes:

publish	0.07
neither	0.11
na	0.07
guess	0.74

See attached csv for the details of the coding.
