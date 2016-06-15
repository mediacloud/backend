This is the source code for the [Media Cloud](http://mediacloud.org/) core system. Media Cloud, a joint
project of the [Berkman Center for Internet & Society at Harvard
University](http://cyber.law.harvard.edu/) and the [Center for Civic Media at
MIT](http://civic.mit.edu/), is an open source, open data platform that allows
researchers to answer complex quantitative and qualitative questions about the
content of online media.

For more information on Media Cloud, go to
[mediacloud.org](http://mediacloud.org/).

**NOTE:** Most users prefer to use Media Cloud's [API and public tools](http://mediacloud.org/get-involved/) to query our data instead of running their own Media Cloud instance. 

The code in this repository will be of interest to those users who wish to run their own Media Cloud instance and users of the public tools who want to understand how Media Cloud is implemented.

The Media Cloud code here does three things:

* Runs a web app that allows you to manage a set of media sources and their
  feeds.
  
* Periodically crawls the feeds setup within the web app and downloads any
  new stories found within the downloaded feeds.
  
* Extracts the substantive text from the downloaded story content (minus
  the ads, navigation, comments, etc) and associates a set of tags
  with each story based on that extracted text.

For very brief installation instructions, see [INSTALL.markdown](INSTALL.markdown).

Please send us a note at [info@mediacloud.org](info@mediacloud.org) if you are
using any of this code or if you have any questions.  We are very interested in
knowing who's using the code and for what.

For a brief roadmap of the code contained in this release, see
[repo-map.markdown](doc/repo-map.markdown).


Build Status
------------

[![Build Status](https://travis-ci.org/berkmancenter/mediacloud.svg?branch=master)](https://travis-ci.org/berkmancenter/mediacloud) 
[![Coverage Status](https://coveralls.io/repos/github/berkmancenter/mediacloud/badge.svg?branch=master)](https://coveralls.io/github/berkmancenter/mediacloud)


History of the Project
----------------------

Print newspapers are declaring bankruptcy nationwide. High-profile blogs are
proliferating. Media companies are exploring new production techniques and
business models in a landscape that is increasingly dominated by the Internet.
In the midst of this upheaval, it is difficult to know what is actually
happening to the shape of our news. Beyond one-off anecdotes or painstaking
manual content analysis, there are few ways to examine the emerging news
ecosystem.

The idea for Media Cloud emerged through a series discussions between faculty
and friends of the Berkman Center. The conversations would follow a predictable
pattern: one person would ask a provocative question about what was happening
in the media landscape, someone else would suggest interesting follow-on
inquiries, and everyone would realize that a good answer would require heavy
number crunching. Nobody had the time to develop a huge infrastructure and
download *all* the news just to answer a single question. However, there were
eventually enough of these questions that we decided to build a tool for
everyone to use.

Some of the early driving questions included:

* Do bloggers introduce storylines into mainstream media or the other way
around?
* What parts of the world are being covered or ignored by different media
sources?
* Where do stories begin?
* How are competing terms for the same event used in different publications?
* Can we characterize the overall mix of coverage for a given source?
* How do patterns differ between local and national news coverage?
* Can we track news cycles for specific issues?
* Do online comments shape the news?

Media Cloud offers a way to quantitatively examine all of these challenging
questions by collecting and analyzing the news stream of tens of thousands of
online sources.

Using Media Cloud, academic researchers, journalism critics, policy advocates,
media scholars, and others can examine which media sources cover which stories,
what language different media outlets use in conjunction with different
stories, and how stories spread from one media outlet to another.


Sponsors
--------

Media Cloud is made possible by the generous support of the [Ford
Foundation](http://www.fordfoundation.org/), the [Open Society
Foundations](http://www.opensocietyfoundations.org/), and the [John D. and
Catherine T. MacArthur Foundation](http://www.macfound.org/).


Collaborators
-------------

Past and present collaborators include [Morningside
Analytics](https://www.morningside-analytics.com/),
[Betaworks](http://betaworks.com/), and [Bit.ly](https://bitly.com/).


License
-------

Media Cloud is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

Media Cloud is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
details.

You should have received a copy of the GNU Affero General Public License along
with Media Cloud . If not, see
<[http://www.gnu.org/licenses/](http://www.gnu.org/licenses/)>.
