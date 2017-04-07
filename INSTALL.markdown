# How to install Media Cloud

These are very brief, likely incomplete, installation instructions.  If you want to install the system, follow these instructions as they are and send any questions to <info@mediacloud.org>.

These instructions assume comfort with PostgreSQL and especially with Perl. You may have a difficult time installing the system if you do not have experience with Perl and cpan.

**Note: these instructions have only been tested on Ubuntu Linux and macOS.** We recommend using Ubuntu 16.04 Xenial Xerus or macOS Sierra 10.12. Earlier versions may be missing some of the necessary packages. Additionally, Media Cloud requires a 64 bit OS.

**Please be aware:** macOS support has been less thoroughly tested than Ubuntu. We hope to improve macOS support in the future but currently some macOS users encounter problems with the install script. Advanced users comfortable with the Darwin command line will probably be able to work around these issues but others may be happier running Ubuntu in a VM if they encounter errors with the macOS install.

If you're running macOS, you'll need [Homebrew](http://mxcl.github.com/homebrew/) to install the required packages. It might be possible to do that manually with [Fink](http://www.finkproject.org/) or [MacPorts](http://www.macports.org/), but you're at your own here. As a dependency of Homebrew, you will also need to install Xcode (available as a free download from Mac App Store or from <http://developer.apple.com/>) and Xcode's "Command Line Tools" (open Xcode, go to *Xcode* -> *Preferences...*, select *Downloads*, choose *Components*, click *Install* near the *Command Line Tools* entry, wait for a while).

**Note:** We recommend you create a new user to run and install Media Cloud. (The new user should have administrator access.) These instructions assume that the user running media cloud does not already have Perlbrew installed. Creating a new user is the safest way to ensure this is the case.

**Warning:** The file path of the directory for Media Cloud cannot contain spaces. E.g. use `/home/bob/MySoftware/mediacloud`, not `/home/bob/My Software/mediacloud`.


## Install

Users who are really impatient can just run a single script to execute the necessary commands to install media by running `./install.sh` from the Media Cloud root directory:

    ./install.sh

You might consider running steps from `install.sh` individually too.

If this script runs successfully, skip to the [Post Install](#post-install) section at the end of this file.

**Note:** default Media Cloud installation is insecure as PostgreSQL users and databases get created with default hardcoded credentials. Make sure to not expose your Media Cloud instance to the public, firewall it accordingly, or change PostgreSQL credentials in `mediawords.yml` and remove default users before proceeding to making Media Cloud public.


## Post Install
  
1. Run `./script/start_mediacloud_server.sh`. This should start up the web server. If the command line returns no errors, go to <http://localhost:5000> (or replace `localhost` with whatever host the system is on) to access the server.

2. To access the administration interface, go to <http://localhost:5000/login> and log in with the email address and password that you've provided before.  If you've used the `./install.sh` script, the default administrator's email address is `jdoe@mediacloud.org` and the password is `mediacloud`.
  
3. The [doc/](doc/) directory contains additional documentation. Refer to the README files in that directory for more information.

4. Perform brilliant analysis, fix our broken code, document how the system works, and otherwise contribute to the project.
