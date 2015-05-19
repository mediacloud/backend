# Setup the temporary crawler

Setup a machine with Ubuntu installed. For example, by creating an AWS instance.

**Make sure that the time zone of your machine is set to Eastern Time.** Run `date` if the result isn't EDT and EST, run `sudo dpkg-reconfigure tzdata` and select America/New_York.
**NOTE: AWS machines are often initially setup with UTC as the timezone instead of Eastern.**

Install Media Cloud on the machine.

cd to the Media Cloud installation directory

Run `python python_scripts/media_import.py`

Start supvisisor by running `./supervisor/supervisord.sh`

Optional: Stop the extractor workers by running `./supervisor/supervisorctl.sh stop extract_and_vector`

Let the crawler on this machine run as long as desired.

# Exporting

When you're ready to export:

Stop the crawler by running `./supervisor/supervisorctl.sh stop mc:crawler`

Export feed_downloads to the production system by running.
`python python_scripts/export_feed_downloads_through_api.py --source-api-key SOURCE_API_KEY --dest-api-key DEST_API_KEY --source-media-cloud-api_url SOURCE_MEDIA_CLOUD_API_URL --dest-media-cloud-api_url DEST_MEDIA_CLOUD_API_URL`

E.g.

`python python_scripts/export_feed_downloads_through_api.py --source-api-key 'e07cf98dd0d457351354ee520635c226acd238ecf15ec9e853346e185343bf7b' --dest-api-key  '1161251f5de4f381a198eea4dc20350fd992f5eef7cb2fdc284c245ff3d4f3ca' --source-media-cloud-api_url  'http://localhost:3000/' --dest-media-cloud-api_url https://api.mediacloud.org/ --db-label  "AWS backup crawler"`
