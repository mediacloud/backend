Authentication / authorization
==============================

Media Cloud contains a basic authentication and authorization system that must be used. At the time of writing, there is no way to explicitly disable the authentication and authorization. Even if you are the only user of your deployment, you still have to create a user for yourself and assign an "admin" role to it.

Quick start
-----------

To add a user with an email address "your@email.com", full name "Your Name",
described as "Media Cloud administrator", having an "admin" role and a
"yourpassword123" password, run:

    ./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
        --action=add \
        --email="your@email.com" \
        --full_name="Your Name" \
        --notes="Media Cloud administrator" \
        --roles="admin" \
        --password="yourpassword123"

To log in, open:

    http://127.0.0.1:5000/login


User management
---------------

You can manage (add, remove, change various properties) users via two
interfaces:

1. Web interface that is available on http://127.0.0.1:5000/admin/users/list,
2. CLI Perl script located at `./script/mediawords_manage_users.pl`.

The user management web interface is self explaining.

For the information on how to use the user management CLI Perl script, please
open script with a text editor and read the documentation on the top of the
file. Alternatively, you can run:

    # user manager's help
    ./script/run_with_carton.sh ./script/mediawords_manage_users.pl --help

or

    # user manager action's help
    ./script/run_with_carton.sh ./script/mediawords_manage_users.pl --action=...
