Deployment
==========

Process
-------

Here is the process for deploying new code to the production server on mcdb1:

1. Merge desired code into the 'release' branch and push the changes to github.

2. Login to mcdb1 and change to the mediacloud account.

3. Change to the /space/mediacloud/mediacloud directory where mediacloud installation resides.

4. Shut down the supervisor daemons: `supervisor/supervisorctl.sh shutdown`.

5. Pull the latest release: `git pull`

6. Check for and manually review postgres updates: `script/run_with_carton.sh script/mediawords_upgrade_db.pl`

7. Run postgres updates (see below): `script/run_with_carton.sh script/mediawords_upgrade_db.pl --import`

8. Start supervisor daemons: `supervisor/supervisord.sh`

9. Logout of mediacloud user.

10. As regular user, restart apache: `sudo apache2ctl restart`

11. Check http://core.mediacloud.org to make sure apache is running happily.

12. As mediacloud, run '/space/mediacloud/mediacloud/supervisor/supervisorctl.sh status' to make sure the supervisor
daemons are running happily.

Postgres Updates
----------------

It is important to remember that once you update the code (`git pull`), new scripts will refuse to run until you have
updated the database version by running mediawords_upgrade_db.pl.  Some database updates may take a long time to run
and not impact any running processes (for instance, adding millions of stories to some processing queue that the update
is creating).  In these cases, it is better to manually run those queries before doing the deployment and then manually
picking out the parts of the database upgrade as printed by mediawords_upgrade_db.pl that still need to be run.  It is
fine to do all of those database updates manually in psql as long as you remember the part of the upgrade sql script
that updates the database version.  Even if the updates do not take a long time, it is okay to do the database updates
minus the version update beforehand to make sure everything is kosher before doing the rest of the deployment.
