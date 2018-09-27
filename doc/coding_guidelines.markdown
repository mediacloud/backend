# Python guidelines

## Python Version

Tests are run on travis using Python 3.5+, though improvements to keep up with modern Python are welcome.

## Code Style

Run `flake8 mediacloud/mediawords` to ensure your code follows our style guide. This is also run on travis.

## Declare Function Parameter and Return Value Types

Python 3 has [type hints](https://docs.python.org/3/library/typing.html), and we should use so that we:

1. Know what kind of parameters does the function expect and get an IDE warning if we're passing the wrong type.
2. Know what does the function return (Is `None` one of the options, or does the function `raise` on errors? Is it a list of dicts or a dict of lists?), and get an IDE warning if we're using the return value in a wrong way (e.g. treating it as a dictionary instead of a list).

```python
# BAD!
def select(table, what_to_select='*', condition_hash):
    # ...
```

```python
# GOOD!
def select(table: str,
           what_to_select: str = '*',
           condition_hash: dict) -> dict:
    # ...
```


### Basic

For parameter / return types, you can define built-in types (`str`, `int`, `list`, `dict`, `bool`, ...) or nested types using helpers from `typing` package, e.g.:

```python
from typing import Any


def a() -> None:
    # Function doesn't return anything.

def b() -> str:
    # Function returns a string (`str`).

def c() -> int:
    # Function returns an integer (`int`).

def d() -> bool:
    # Function returns a boolean (`bool`).

def e() -> list:
    # Function returns a free-form list (`list`).
    # (if you can predict the types of list items, consider using `List`)

def f() -> dict:
    # Function returns a free-form dictionary (`dict`).
    # (if you can predict the types of dictionary keys / values, consider using `Dict`)

def m(arg1: CustomType) -> None:
    # `arg1` is expected to be an object of type `CustomType`.
    # Function doesn't return anything.

def n(arg1: Any) -> None:
    # `arg1` is expected to be of any type (generally discouraged though).
    # Function doesn't return anything.
```


### Subtypes

```python
from typing import Dict, List, Union


def g() -> Union[str, None]:
    # Function returns either a 'str' value or `None`.

def h(arg1: Dict[str, int]) -> None:
    # `arg1` is expected to be a `dict` with `str` keys and `int` values.
    # Function doesn't return anything.

def i(arg1: List[str]) -> None:
    # `arg1` is expected to be `list` with `str` items.
    # Function doesn't return anything.

def j(arg1: List[Dict[str, int]]) -> None:
    # `arg1` is expected to be a `list` of `dict`s with `str` keys and `int` values.
    # Function doesn't return anything.
```


### Subtypes of Argument Functions

```python
from typing import Callable


def k(arg1: Callable[[], None]) -> None:
    # `arg1` is expected to be a function which:
    #     * doesn't have parameters, and
    #     * doesn't return anything.
    # Function doesn't return anything.

def l(arg1: Callable[[str, int], bool]) -> None:
    # `arg1` is expected to be a function which:
    #     * accepts two parameters - `str` and `int`, and
    #     * returns `bool`.
    # Function doesn't return anything.
```


## Write documentation

Describe what your functions / methods / classes / whatnot are doing **and why they're doing that**, so that others (including you in a couple of months) would be able to figure out what the code is all about without reading through the implementation. Start the docstring with a capital letter, end it with a period, wrap it around 120 lines as per PEP 8:

```python
# BAD!
def do_stuff(param_1: int, obj: SomeSortOfObject, some_other_param: tuple) -> bool:
    # No docstring, code that does strange stuff in the next 600 lines follows
    ...
```

```python
# GOOD!
def do_stuff(param_1: int, obj: SomeSortOfObject, some_other_param: tuple) -> bool:
    """Short summary of what does the function do.

    Extended description of the minutiae of the function (if applicable) and an
    explanation of function's purpose in a bigger picture."""
    ...
```


## Use dictionary-style arguments for psycopg2 queries

This single style is very flexible, avoids using tuples, and is verbose enough for the IDE to help you catch errors:

```python
# GOOD!
db.query(

    # Please note the comma between SQL query and it's parameters.
    #
    # If the comma was replaced with '%', Python interpreter instead
    # of psycopg2 would do the interpolation, and that would lead
    # to an error.
    
    'SELECT * FROM foo WHERE bar = %(bar)s AND baz = %(baz)s',
    { 'bar': bar, 'baz': baz }
)
```


## Throw Custom Exceptions

On multiple occasions in the code, we have a need to find out:

* What kind of an error was thrown?
* Was it a critical error, i.e. can we retry or is it not worth it to continue further?

To make debugging easier, consider defining and throwing custom exceptions instead of just `Exception`:

```python
class McResearchException(Exception):
    """Problems in research()."""
    pass

class McResearchSoftFailureException(McResearchException):
    """Recoverable problems in research()."""
    pass

class McResearchHardFailureException(McResearchException):
    """Unrecoverable problems in research()."""
    pass


def research():
    """Do important researchy stuff."""
    if network.down():
        raise McResearchSoftFailureException(
            "Network is down, but it's worth retrying."
        )
    
    if funding.gone():
        raise McResearchHardFailureException(
            "Well, we'll have to just stop here."
        )

retries = 3
for retry in range(0, 3):
    while True:
        try:
            research()
        except McResearchSoftFailureException as ex:
            l.info("Something has failed while doing research, but I'll retry: %s" % str(ex))
            continue
        except McResearchHardFailureException as ex:
            l.error("Critical error while doing research, can't continue: %s" % str(ex))
            sys.exit(1)

        l.info("Research completed, time to get published!")
        break

```


## Write Unit Tests

To be able to modify the underlying implementation of our code and not break the brittle crystal castles that make this code up, we need to cover it with unit tests.

Writing those tests is definitely a burden, especially when put under time constraints and looming deadlines, but so is:

* time and effort spent recovering from buggy code,
* time and effort spent figuring out what was meant by the code written in 2008,
* time and effort spent postponing feature release because the code changed is untested so there's no confidence that it will work (continue working) as expected.

Tips on writing useful unit tests:

* Write the test **first** and only then implement the required functionality.
    * It's easier to postpone the testing indefinitely if the test is to be done "later".
    * Instead of a burden, an unit test should be a tool for the developer to test the code.
* Write **unit** tests, distinguish them from integration tests.
    * Wikipedia defines a *unit* as *the smallest testable part of an application*. Thus, functionality spanning three modules and 3000 code lines is not much of a unit.
    * Integration tests are at the very least:
        * slow (as they test a lot of code at once),
        * unable to cover all border cases of a single unit (a function or a method),
        * hard to debug (typically, the integration test is able to report only that the code failed, not where and why it had done so)
    * ...so while still tremendously useful, they're not a good replacement for having unit tests
* Make unit tests **atomic**
    * ...meaning that a single test should be testing only a small part of the functionality, e.g. a function or a class method
* Make unit tests **isolated**
    * A unit test can't depend on it being run in a particular order with other tests
* If the code does not feel like it's easily testable, consider refactoring said code


## Use Nose's Test Naming Syntax

### Keep unit tests in the same directory, prefix file names with `test_`

For example, unit tests for module `foo.py` should be kept in file `test_foo.py`.

### Keep unit test functions separate

Nose will automatically run all functions that start with `test_`:

```python
# BAD!
def __test_this():
    # Do some testing

def __test_that():
    # Do some more testing

def test_everything_at_once():
    __test_this()
    __test_that()
```

```python
# GOOD!
def test_this():
    # Do some *self contained* testing

def test_that():
    # Do some more *self contained* testing
```

This makes it easier to run a single test from an IDE instead of the full suite.

If you need to do any preparations for the test that is being run, create a `TestCase` class and implement `setUp()` and `tearDown()` (see below).

### Test utility modules with a flat test files

Module `badger.py`:

```python
def foo():
    # ...

def bar():
    # ...

def baz():
    # ...
```

Test file `test_badger.py`:

```python
from badger import foo, bar, baz


def test_foo():
    assert foo('xyz') == 'abc'

def test_bar():
    # ...

def test_baz():
    # ...
```

### Test classes with test classes

Module `research.py`:

```python
class Research(object):
    
    def research_something(self):
        # ...

    def get_funding(self):
        # ...

    def make_powerpoint_presentation(self):
        # ...
```

Test file `test_research.py`:

```python
from unittest import TestCase

from research import Research


class TestResearch(TestCase):
    __research = None

    def setUp(self):
        # Run before every test
        # (it is not neccessary to create a object that's being tested in
        # setUp() and use it in the test class, this is just a showcase that
        # setUp() exists.)
        self.__research = Research()

    def tearDown(self):
        # Run after every test
        # ...

    def test_research_something(self):
        assert self.research_something() == 42

    def test_get_funding(self):
        # ...

    def test_make_powerpoint_presentation(self):
        # ...
```


## Contain External Dependencies in Wrappers

In other words, don't pass around objects coming from external dependencies throughout the code.

Quote often we decide to change underlying third party tool with an alternative choice (e.g. remember Gearman or MongoDB GridFS). Doing so when direct usages of the tool scattered all around the code is tremendously hard and error-prone:


```python
# BAD!

import requests

def fetch_url(url: str) -> requests.Response:
    return requests.get(url)

response = fetch_url('http://www.mediacloud.org/')
response_text = response.text

# 'response' is now of type requests.Response, thus making 'requests' module
# forever ingrained into our code. Good luck changing it to an alternative!

```

```python
# GOOD!

import requests

class FetchURLResponse(object):

    __requests_response = None

    def __init__(self, requests_response: requests.Response):
        self.__requests_response = requests_response

    def text(self) -> str:
        return self.__requests_response.text

def fetch_url(url: str) -> requests.Response:
    return FetchURLResponse(requests.get(url))

response = fetch_url('http://www.mediacloud.org/')
response_text = response.text()

# With five minutes of writing extra binding code, you've just saved someone
# (very likely yourself) a whole week of head bashing!

```

----

# Perl Guidelines

## File Prefix

All source files must use the CPAN module `Modern::Perl` and the internal library `MediaWords::CommonLibs`. Thus the
following should be present at the beginning of the file:

    use Modern::Perl "2015"; use MediaWords::CommonLibs;

Simply including these modules will, among other things, enable all Perl 5.20 features, provide common and frequently
used libraries such as `Readonly` and `Data::Dumper`, and ensure use strict is enabled.

Any source files that do not use `Modern::Perl` and `MediaWords::CommonLibs` must have a comment explaining why these
libraries are not being used.

## Shebang Lines

In order to ensure that scripts can be run with perlbrew the Perl location in the shebang line should be determined by
the environment rather than being hard coded. Instead of `#!/usr/bin/perl` use `#!/usr/bin/env perl`

## Code Formatting

The git repository is set to automatically call `reformat_code.pl` on every perl file before every commit.

`reformat_code.pl` uses the `Perl::Tidy` module to automatically reformat the code according to a set of
rules defined in the perltidy config file at `script/perltidy_config_file`. This file along with the Perl
Tidy documentation is considered the authoritative version of the code formating rules. Some of the rules defined in
this file are use spaces instead of tabs, 125 character maximum line length, 4 character indentation, BSD/ANSI style in
which braces appear on a line by themselves and code is indented inside braces.

## Other Guidelines

* Comment scripts and modules - start every module / script with a comment describing what the script does, ideally
in a few lines at most.

* Use a main function - put all code that the script will execute into a `main()` function at the bottom of the script
so that we don't have to hunt through a long script to find the executing code among the function definitions. For
example:

```perl
sub main
{
   my $crawler = MediaWords::Crawler::Engine->new();

   $crawler->crawl();
}

main();
```

* Write self commenting code - Try to write your code so that it does not need comments to be grokkable. If there's a
big block of code that needs explanation, break out discrete blocks into their own, clearly named, functions that tell
the story of what the code is doing. A rule of thumb is that no single function should be longer than a single screen.

* Comment every function - Add a brief (generally one line, up to a few lines) comment before every function definition.

----

# SQL Guidelines

* Every table name should be plural (`stories` not `story`).

* Mapping tables should be names `*table1*_*table2*_map` (for example `stories_tags_map`).

* Other than mapping tables or for good performance reasons, every table should have a serial primary key called `*table*_id` (for example `stories_id`).

* Always follow proper denormalization principles unless there's a good reason not to.
