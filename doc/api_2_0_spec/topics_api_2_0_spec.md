[TOC]

# Overview

This document described the Media Cloud Topics API.  The Topics API is a subset of the larger Media Cloud API.  The Topics API provides access to data about Media Cloud Topics and related data.  For a fuller understanding of Media Cloud data structures and for information about *Authentication*, *Request Limits*, the API *Python Client*, and *Errors*, see the documentation for the main [link: main api] Media Cloud API.

The topics api is currently under development and is available only to Media Cloud team members and select beta testers.  Email us at info@mediacloud.org if you would like to beta test the Topics API.

A *topic* currently may be created only by the Media Cloud team, though we occasionally run topics for external researchers.



## Media Cloud Crawler and Core Data Structures

The core Media Cloud data are stored as *media*, *feeds*, and *stories*.  

A *medium* (or *media source*) is a publisher, which can be a big mainstream media publisher like the New York Times, an
activist site like fightforthefuture.org, or even a site that does not publish regular news-like stories, such as
Wikipedia.  

A *feed* is a syndicated feed (RSS, RDF, ATOM) from which Media Cloud pulls stories for a given *media source*.  A given
*media source* may have anywhere from zero *feeds* (in which case we do not regularly crawl the site for new content) up
to hundreds of feeds (for a site like the New York Times to make sure we collect all of its content).

A *story* represents a single published piece of content within a *media source*.  Each *story* has a unique url within
a given *media source*, even though a single *story* might be published under multiple urls.  Media Cloud tries
to deduplicate stories by title.

The Media Cloud crawler regularly downloads every *feed* within its database and parses out all urls from each *feed*.
It downloads every new url it discovers and adds a *story* for that url, as long as the story is not a duplicate for
the given *media source*.  The Media Cloud archive consists primarily of *stories* collected by this crawler.

## Topic Data Structures

A Media Cloud *topic* is a set of stories relevant to some subject.  The topic spider starts by searching for a
set of stories relevant to the story within the Media Cloud archive and then spiders urls from those
stories to find more relevant stories, then iteratively repeats the process 15 times.

After the spidering is complete, a *topic* consists of a set of relevant *stories*, *links* between those stories, the
*media* that published those *stories*, and social media metrics about the *stories* and *media.  The various topics/
end points provide access to all of this raw data as well as various of various analytical processes applied to this
data.

## API URLs

All urls in the topics api are in the form:

https://api.mediacloud.org/api/v2/topics/<topics_id>/stories/list?key=KEY

For example, the following will all stories in the latest snapshot of topic id 1344.

https://api.mediacloud.org/api/v2/topics/1344/stories/list?key=KEY

## Snapshots, Timespans, and Frames

Each *topic* is viewed through one of its *snapshots*.  A *snapshot* is static dump of all data from a topic at
a given point in time.  The data within a *snapshot* will never change, so changes to a *topic* are not visible
until a new *snapshot* is made.

Within a *snapshot*, data can be viewed overall, or through some combination of a *frame* and a *timespan*.

A *frame* consists of a subset of stories within a *topic* defined by some user configured *framing method*.  For
example, a 'trump' *frame* within a 'US Election' *topic* would be defined using the 'Boolean Query' *framing method*
as all stories matching the query 'trump'.  *Frames* can be collected together in a *Frame Set* for easy comparison.

A *timespan* displays the *topic* as if it exists only of stories either published within the date range of the
*timespan* or linked to by a story published within the date range of the *timespan*.

*Topics*, *snapshots*, *frames*, and *timespans* are strictly hierarchical.  Every *snapshot* belongs to a single
*topic*.  Every *frame* belongs to a single *snapshot*, and every timespan* belongs to either a single *frame* or the
*null *frame*.  Specifying a *frame* implies the parent *snapshot* of that *frame*.  Specifying a *topic* implies the
*parent *frame* (and by implication the parent *snapshot*), or else the null *frame* within the parent *snapshot*.

## Common Parameters

Every url that returns data from a *topic* accepts optional *spanshots_id*, *timespans_id*, and *frames_id* parameters.

If no *snapshots_id* is specified, the call returns data from the latest *snapshot* generated for the *topic*.  If no
*timespans_id* is specified, the call returns data from the overall *timespan* of the given *snapshot* and *frame*.  If
no *frames_id* is specified, the call assumes the null *frame*.  If multiple of these parameters are specified,
they must point to the same *topic* / *snapshot* / *frame* / *timespan* or an error will be returned (for instance, a
call that specifies a *snapshots_id* for a *snapshot* in a *topic* different from the one specified in the url, an error
will be returned).

# Topics

## topics/list

The topics/list call returns a simple list of topics available in Media Cloud.  The topics/list call is is only call
that does not include a topics_id in the url:

https://api.mediacloud.org/api/v2/topics/list

### Query Parameters

(no parameters)

### Output Description



END
