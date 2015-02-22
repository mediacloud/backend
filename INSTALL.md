# INSTALLATION INSTRUCTIONS

These are very brief, likely incomplete, installation instructions.  If you
want to install the system, follow these instructions as they are and
send any questions to info@mediacloud.org.

These instructions assume comfort with PostgreSQL and especially with Perl. You
may have a difficult time installing the system if you do not have experience
with Perl and cpan.

**NOTE:** THESE INSTRUCTIONS HAVE ONLY BEEN TESTED ON UBUNTU LINUX AND MAC OS X. We recommend using Ubuntu 12.04 (Precise Pangolin) or Mac OS X 10.7 Lion. Earlier versions may be missing some of the necessary packages. Additionally, Media Cloud requires a 64 bit OS.

**BE AWARE THAT:** Mac OS X support has been less thoroughly tested than Ubuntu. We hope to improve OS X support in the future but currently some OS X users encounter problems with the install script. Advanced users comfortable with the Darwin command line will probably be able to work around these issues but others may be happier running Ubuntu in a VM if they encounter errors with the OS X install.

If you're running Mac OS X, you'll need Homebrew <http://mxcl.github.com/homebrew/> to install the required packages. It might be possible to do that manually with Fink <http://www.finkproject.org/> or MacPorts <http://www.macports.org/>, but you're at your own here. As a dependency of Homebrew, you will also need to install Xcode (available as a free download from Mac App Store or from http://developer.apple.com/) and Xcode's "Command Line Tools" (open Xcode, go to "Xcode" -> "Preferences...", select "Downloads", choose "Components", click "Install" near the "Command Line Tools" entry, wait for a while).

**NOTE:** We recommend you create a new user to run and install Media Cloud. (The new user should have administrator access.) These instructions assume that the user running media cloud does not already have Perlbrew installed. Creating a new user is the safest way to ensure this is the case.

**WARNING:** The file path of the directory for Media Cloud cannot contain spaces. E.g. use '/home/bob/MySoftware/mediacloud' not '/home/bob/My Software/mediacloud'.

## SUPER QUICK START

We recommend that you first read through this entire file. However, users who are really impatient can just run a single script to execute the necessary commands to install media by running ./install.sh from the Media Cloud root directory:

     ./install.sh

This script simply runs the commands given in the quick start section below.

If this script runs successfully, skip to the POST INSTALL section at the end of this file.

## QUICK START

We recommend that you read through this entire file. Nevertheless most users will be able to simply run the following commands from the Media Cloud root directory:

     sudo ./install_scripts/install_mediacloud_package_dependencies.sh
     sudo ./install_scripts/create_default_db_user_and_databases.sh 
     cp  mediawords.yml.dist mediawords.yml
     ./install_mc_perlbrew_and_modules.sh
     ./python_scripts/pip_installs.sh
     ./script/run_carton.sh exec prove -Ilib/ -r t/compile.t
     ./script/run_with_carton.sh ./script/mediawords_create_db.pl
     ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
         --action=add \
         --email="your@email.com" \
         --full_name="Your Name" \
         --notes="Media Cloud administrator" \
         --roles="admin" \
         --password="yourpassword123"

After you have successfully run the above commands, skip to the POST INSTALL section at the end of this file.

## DETAILED INSTALL

* Install the necessary Ubuntu deb packages. From the Media Cloud root directory, run:

        sudo ./install_scripts/install_mediacloud_package_dependencies.sh

This will install PostgreSQL 9.1+ and a number of system libraries needed by CPAN modules.

* Create the default PostgreSQL user and databases for Media Cloud. From the Media Cloud root directory, run:

        sudo ./install_scripts/create_default_db_user_and_databases.sh 

This will create a PostgreSQL user called 'mediaclouduser' and two databases owned by this user: mediacloud and mediacloud_test.

* Copy mediawords.yml.dist to mediawords.yml.

* SECURITY NOTE: The PostgreSQL user created above has a default PostgreSQL password and will have administrative access to PostgreSQL. These instructions assume that Media Cloud is being installed on a system with firewalls that prevent remote access to PostgreSQL and that the local users are trustworthy. If you wish to change the password of the PostgreSQL 'mediaclouduser' in PostgreSQL, you will also need to edit mediawords.yml.

* Optional: Update the database section in mediawords.yml. Most users can skip this step and use the defaults. However, if you have changed the password of the PostgreSQL's 'mediaclouduser' or if you have a custom database setup, you must update mediawords.yml. NOTE: The label field for the test database must be 'test' and the test database must be listed after the main database.

* OPTIONAL: Edit the other sections of mediawords.yml to suit your local configuration.  
  NOTE THAT if you uncomment a suboption, you also need to uncomment the parent option.  For example, if you uncomment 'default_tag_module', you should also uncomment 'mediawords'.
  
* OPTIONAL: If you want to use calais tagging, you'll need to apply for a calais key 
  and enter the key into mediawords.yml.  Then change 'NYTTopics' for the
  default_tag_modules setting to 'NYTTopics Calais',

*  Run the install_mc_perlbrew_and_modules.sh script. This scripts installs Perlbrew, carton and the required modules. I.E. simply CD to the base directory of Media Cloud and run the following. Note that the script will take a long time to complete:

         ./install_mc_perlbrew_and_modules.sh

*  Run the python_scripts/pip_install.sh script. This scripts installs Python modules through pip. I.E. simply CD 
to the base directory of Media Cloud and run the following. Note that the script will take a long time to complete:

         ./python_scripts/pip_installs.sh

NOTE this script will fail if you aren't running a 64 bit OS.

* SUGGESTED: Verify that the necessary modules are installed. Run the media cloud compile test to verify that all required modules have been installed. Run:

        ./script/run_carton.sh exec prove -Ilib/ -r t/compile.t

If there are errors determine which modules are missing and install them by running carton install.

* Make sure that the directory in which Media Cloud is located can be read by the postgres user. Run something like the following:
    
        chmod +rx ~/

* Run the following:

        ./script/run_with_carton.sh ./script/mediawords_create_db.pl

  This will create create the necessary database tables and procedures within the database you specified above.  Answer 'yes' at the prompt since the database you created above should be empty.

* Create the initial administrator user so you can access the administration interface. Run the following:

        ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
            --action=add \
            --email="your@email.com" \
            --full_name="Your Name" \
            --notes="Media Cloud administrator" \
            --roles="admin" \
            --password="yourpassword123"

  Replace "email", "full_name", "notes" and "password" fields with the appropriate information (your email address, full name, ...)

  Alternatively, you can skip the "--password=..." parameter so you can securely enter your password directly.

## POST INSTALL
  
* Run `./script/start_mediacloud_server.sh`.  This should start up the web server.
  If the command line returns no errors, go to http://localhost:5000 
  (or replace localhost with whatever host the system is on) to
  access the server.

* To access the administration interface, go to http://localhost:5000/login and log in with the email address and password that you've provided before.  If you've used the ./install.sh script, the default administrator's email address is "jdoe@mediacloud.org" and the password is "mediacloud".
  
* THE doc/ DIRECTORY CONTAINS ADDITIONAL DOCUMENTATION. Refer to the README files in that directory for more information.

* Perform brilliant analysis, fix our broken code, document how the system
  works, and otherwise contribute to the project.
