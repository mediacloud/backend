Validation
==========

Media Cloud consists of many systems (cf. [story_processing_flow](../doc/story_processing_flow.markdown) and
[controversies](../doc/controversies.markdown)) that work to generate structured data out of unstructured data on
the open web.  Most of those systems have to try to solve problems for which there is no perfect answer.  So our
philosophy is to build systems that work as well as possible with as little long term maintenance as possible and to
validate how well each system works so that we at least know what results we are getting.

In the past, we have done this work in the background, but in the interest of transparency, we are starting to document
that validation work for various systems in this directory.  You should expect to find in each subdirectory of the
validate/ directory a document describing

* what problem we are trying to solve,
* the metric for success solving that problem,
* the method for measuring that metric,
* results measuring the metric, and ,
* any data files we used in the validation process.
