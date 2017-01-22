# Python guidelines

On the best effort basis, you should:


## Use PyCharm

[PyCharm](https://www.jetbrains.com/pycharm/) is (arguably) the best Python IDE around, and there's no reason to not use it. There's a Community Version available for free, and we might even consider applying for their [open source license](https://www.jetbrains.com/buy/opensource/) too.


## Format code with PEP 8

[PEP 8](https://www.python.org/dev/peps/pep-0008/) is the go-to style guide for Python code, so let's not reinventing the wheel.

If using PyCharm (which you should), it's easy to reformat your code by pressing `⌥⌘L` on OS X or `Ctrl + Alt + L` on Linux. Also, PyCharm will help you fix other PEP 8 mistakes automatically.

There's no annoying pre-commit hook which would slow you down by asking to format the code properly, so make it into a habit to press this shortcut early and often.


## Write code with no warnings

If using PyCharm, you'll see warnings on the top right corner of the editor view if you do something funny with your code:

![PyCharm reporting a warning](coding_guidelines/pycharm-warning.png)

Let's just not have those and target for a nice green arrow:

![PyCharm reporting no warnings](coding_guidelines/pycharm-no-warnings.png)

On one-off cases, you can disable a specific warning by adding an annotation for an IDE to suppress this particular warning:

![PyCharm "suppress warning" menu](coding_guidelines/pycharm-suppress-warning.png)

...however don't cheat and write good code instead (declare abstract methods, use preferred syntax, etc.)


## Use named arguments

Named arguments allow one to figure out what is being passed to the function without reading that function's definition.

```python
# BAD!
do_something(42, True, True, False, -1.22, 'badger')
```

```python
# GOOD!
select(table='badgers',
       what_to_select='*',
       condition_hash={'name': 'Bob'})
```

Unless you pass a single argument and it's absolutely trivial what it's about (e.g. `strip_html(html)`), use named parameters.


## Declare function parameter and return values

Python 3 has [type hints](https://docs.python.org/3/library/typing.html), and we should use so that we:

1. Know what kind of arguments does the function expect and get an IDE warning if we're passing the wrong type.
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

For argument / return types, you can define built-in types (`str`, `int`, `list`, `dict`, `bool`, ...) or nested types using helpers from `typing` package, e.g.:

```python
from typing import Dict, Callable, List

def a(arg1: List[Dict[str, int]]) -> None:
	# 'arg1' is expected to be a `list` of `dict`s with `str` keys
	# and `int` values, and we aren't returning anything in this
	# function

def b(arg2: Callable[[], None]):
	# 'arg2' is expected to be a function with no arguments and
	# nothing to return
```


## Throw custom exceptions

On multiple occasions in the code, we have a need to find out:

* What kind of an error was thrown?
* Was it a critical error, i.e. can we retry or is it not worth it to continue further?

To make debugging easier, consider defining and throwing custom exceptions instead of just `Exception`:

```python
class McBadgerException(Exception):
	"""Problems in badger()."""
	pass

class McBadgerSoftFailureException(McBadgerException):
	"""Recoverable problems in badger()."""
	pass

class McBadgerHardFailureException(McBadgerException):
	"""Unrecoverable problems in badger()."""
	pass


def badger():
	if network.down():
		raise McBadgerSoftFailureException(
			"Network is down, but it's worth retrying."
		)
	
	if funding.gone():
		raise McBadgerHardFailureException(
			"Well, we'll have to just stop here."
		)
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

The git repository is set to automatically call `mediawords_reformat_code.pl` on every perl file before every commit.

`mediawords_reformat_code.pl` uses the `Perl::Tidy` module to automatically reformat the code according to a set of
rules defined in the perltidy config file at `script/mediawords_perltidy_config_file`. This file along with the Perl
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
