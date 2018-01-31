# Guidelines for Contributing

Media Cloud welcomes contributions from interested individuals or groups. These guidelines are provided to give potential contributors information to make their contribution compliant with the conventions of the PyMC3 project, and maximize the probability of such contributions to be merged as quickly and efficiently as possible.

There are 4 main ways of contributing to the PyMC3 project (in descending order of difficulty or scope):

* [Adding new](https://github.com/berkmancenter/mediacloud/pulls) or improved functionality to the existing codebase
* Fixing [outstanding issues](https://github.com/berkmancenter/mediacloud/issues) (bugs) with the existing codebase. They range from low-level software bugs to higher-level design problems.
* Contributing or improving the documentation (`doc`)
* Submitting [issues](https://github.com/berkmancenter/mediacloud/issues) related to bugs or desired enhancements

# Python Quickstart

Media Cloud is transitioning from a Perl codebase to a Python one, and prefers new contributions to be written in Python. In order to get working, you may

1. **Get the code**:

	```bash
	$ git clone git@github.com:berkmancenter/mediacloud.git
	$ cd mediacloud/
	```

2. **Install Python libraries**  Note that you likely want to be using something like [virtualenv](https://virtualenv.pypa.io/en/stable/), [conda](https://conda.io/docs/index.html), [pipenv](https://github.com/pypa/pipenv), or [pyenv](https://github.com/pyenv/pyenv) to isolate this environment.

	```
	$ pip install -r mediacloud/requirements.txt
	```

3. **Set up database** Media Cloud uses and runs tests against [PostgreSQL](https://www.postgresql.org/), and assumes port 5432 by default.

	```bash
	$ createuser --superuser mediaclouduser
	$ createdb mediacloud
	$ createdb mediacloud_test
	```

4. **Run tests** The test suite should now pass.

	```bash
	$ py.test -v mediacloud/mediawords
	```

# Opening issues

We appreciate being notified of problems with the existing Media Cloud code, and the best place for that is the [Github Issue Tracker](https://github.com/berkmancenter/mediacloud/issues).


# Contributing code via pull requests

While issue reporting is valuable, we strongly encourage users who are inclined to do so to submit patches for new or existing issues via pull requests. This is particularly the case for simple fixes, such as typos or tweaks to documentation.

## Steps to contribute:

### Setup: 

This needs to be run once:


1. Fork the [project repository](https://github.com/berkmancenter/mediacloud) by clicking on the 'Fork' button near the top right of the main repository page. This creates a copy of the code under your GitHub user account.

2. Clone your fork of Media Cloud, and add the base repository as a remote:

   ```bash
   $ git clone git@github.com:<your GitHub handle>/mediacloud.git
   $ cd mediacloud
   $ git remote add upstream git@github.com:berkmancenter/mediacloud.git
   ```

3. Install the project, as in the Python Quickstart section.


### Develop: 
Follow this loop while developing:

1. Create a `feature` branch to hold your development changes:

   ```bash
   $ git checkout -b my-feature
   ```

2. Fetch and incorporate changes from upstream:

	```bash
	$ git fetch upstream
	$ git rebase upstream/master
	```

3. Write your code and tests. Add changed files with `git add`, and then `git commit`:

   ```bash
   $ git add modified_files
   $ git commit
   ```

4. Run the test suite and check for code style. Note that this is only a subset of the full test suite:
	
	```bash
	$ py.test -v mediacloud/mediawords/
	$ flake8 mediacloud/mediawords/
	```

5. Once tests pass, push the changes to your Github account:

   ```bash
   $ git push -u origin my-feature
   ```

6. Go to the GitHub web page of your fork of the Media Cloud repo. Click the 'Pull request' button to send your changes to the project's maintainers for review. This will send an email to the committers, as well as kick off the full test suite on [Travis](https://travis-ci.org/berkmancenter/mediacloud).


#### This guide was derived from the [scikit-learn guide to contributing](https://github.com/scikit-learn/scikit-learn/blob/master/CONTRIBUTING.md)
