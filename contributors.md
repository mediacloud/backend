Contributing to Media Cloud
===========================

Thanks for wanting to help Media Cloud! 👍👍🏿👍🏻👍🏽


What should I know before I get started?
----------------------------------------

Media Cloud is a big research project.  The two big codebases are the back-end (this repo), and the [front-end web-based tools](https://github.com/mitmedialab/MediaCloud-Web-Tools/). There are also a number of related open-source Pyton packages that we have spun off and use as part of our processing pipeline. 

The back-end is a pretty big codebase and can be daunting to jump into.  You might want to check out one of the related repositories as an easier starting point if you want to help:
* [Feed Seeker](https://github.com/mitmedialab/feed_seeker) - Find RSS, Atom, XML, and RDF feeds on webpages.
* [Date Guesser](https://github.com/mitmedialab/date_guesser) - A library to extract a publication date from a web page, along with a measure of the accuracy.
* [NYT Theme Labeler](https://github.com/mitmedialab/MediaCloud-NYT-News-Labeler) - Tag news stories based on models trained on the NYT corpus.
* [CLIFF](https://github.com/mitmedialab/CLIFF) - A lightweight server to allow HTTP requests to the Stanford Named Entity Recognized and a heavily modified CLAVIN geoparser.
* [Multilingual Sentence Splitter](https://github.com/berkmancenter/mediacloud-sentence-splitter) - Text to sentence splitter using heuristic algorithm by Philipp Koehn and Josh Schroeder.
* [Hausa Stemmer](https://github.com/berkmancenter/mediacloud-hausastemmer) - Hausa language stemmer (Bimba et al., 2015).
* [p5-Lingua-Stem-Snowball-Ca](https://github.com/berkmancenter/p5-Lingua-Stem-Snowball-Ca) - Perl interface to Snowball stemmer for the Catalan language.

> **Note:** We are in the middle of a multi-yeear project to port this code from Perl to Python 3. If you see old Perl code, don't be scared! Be assured that we have a task in the queue to port it over eventually. We have some bindings that let them talk to each other.


How Can I Contribute?
---------------------

**Look for issues marked `good first issue`**.

In this repo, and the others linked to above, look for issues marked with the `good first issue` label.  These are ones that we think are good entry points for someone interested in jumping into the code.


### Pull Requests

In general, it is good practice to fork the repo to your account, make changes on a new branch named after the issue in some way, and then send us a PR back to the main repo.  One of us will review it and then send feedback.

### Installing the Core Backend

One reason that we recommend starting work on some of the smaller repos listed above is that working within the [core backend codebase](https://github.com/berkmancenter/mediacloud) requires installing the entire large platform on you dev machine.  If there is an issue you want to work on in that core backend code, the easiest way to install working version of the codebase with minimal impact on your dev machine is to use Vagrant, as described [here](https://github.com/berkmancenter/mediacloud/blob/master/doc/vagrant.markdown).

### Communicate with the Team

The best way to communicate with the team about Media Cloud code is through the GitHub issues board of the relevant repo.  You might also want to join our [user group](https://groups.io/g/mediacloud), though that group is for users rather than coders, so code questions should be directed to the GitHub issues board.
