Adding new modules (dependencies)
=================================

The Carton module dependency manager depends on two files:

* `cpanfile` -- human-edited list of Perl module dependencies for Media Cloud.
* `cpanfile.snapshot` -- auto-generated list of modules, their versions and
  dependencies used by Carton to install a specific version of the module in
  each of the developer's machines.

So, to add a new Perl module dependency:

1. Add a dependency to this `cpanfile` (make sure to keep the list in
alphabetical order for easier merges):

        ...
        requires 'Your::Module';
        ...

2. Install the dependency using Carton while also regenerating the
   `cpanfile.snapshot` file:

        ./script/run_carton.sh install

3. Commit both files:

        # Git
        git add cpanfile cpanfile.snapshot
        git commit

See [cpanfile documentation on CPAN](http://search.cpan.org/~miyagawa/Module-CPANfile-0.9031/lib/cpanfile.pod)
for more information about the `cpanfile` file format.


Updating modules to new versions
================================

To update Perl modules to their new versions:

1. Run the updater script:

        ./script/update_modules_with_carton.sh

2. Run the test suite to make sure the modules work alright:

        ./script/run_carton.sh exec prove -Ilib/ -r t/compile.t
        ./script/run_test_suite.sh

3. Commit the updated `cpanfile.snapshot`:

        # Git
        git add cpanfile.snapshot
        git commit


Running Scripts
===============

95% of the time you'll just use the `run_with_carton.sh` wrapper to run scripts:

    ./script/run_with_carton.sh ./script/SCRIPT_NAME.pl ARG1 ARG2

Note it's best to run this script from the base directory of the Media Cloud
install. However, this only matters if the arguments after the script are file
paths.


Debugging
=========

To run a script with the debugger under Carton, use
`./script/debug_with_carton.sh`:

    ./script/debug_with_carton.sh ./script/SCRIPT_NAME.pl ARG1 ARG2

You can invoke this script with the same arguments you used for
`run_with_carton.sh`.


Profiling
=========

To profile execution with `Devel::NYTProf`, use
`./script/profile_with_carton.sh`:

    ./script/profile_with_carton.sh ./script/SCRIPT_NAME.pl ARG1 ARG2

You can invoke this script in the same manner as `run_with_carton.sh` and
`debug_with_carton.sh`.


The Gory Details
================

`debug_with_carton.sh` and `run_with_carton.sh` work by invoking a special
version of Carton that we've modified to examine the environment variable
`CARTON_EXTRA_PERL5OPT`.

Everything in this variable is appended to `PERL5OPT` by our Carton before it
executes the given Perl script.

You can use this special Carton with `./script/run_wrappered_carton.sh`. For
example, to have `SCRIPT_NAME.pl` be invoked with the module `Foo::Bar`, you
would do the following:

    CARTON_EXTRA_PERL5OPT="-mFoo::Bar" \
    ./script/run_wrappered_carton.sh exec ./script/SCRIPT_NAME.pl ARG1 ARG2
