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

# SQL Guidelines

* Every table name should be plural ('stories' not 'story').

* Mapping tables should be names *table1*_*table2*_map (for example 'stories_tags_map').

* Other than mapping tables or for good performance reasons, every table should have a serial primary key called *table*_id (for example 'stories_id').

* Always follow proper denormalization principles unless there's a good reason not to.
