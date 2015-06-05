# Setup the temporary crawler

1. Setup a machine with Ubuntu installed. For example, by creating an AWS instance.

 **NOTE:** make sure the machine has sufficient disk space. For example, if using AWS, you will need to either create the instance with a large root partition or mount additional storage and use symlinks to get Postgresql to use this storage instead of the root partition.

2. **Make sure that the time zone of your machine is set to Eastern Time.** Run `date`, if the result isn't EDT or EST, run `sudo dpkg-reconfigure tzdata` and select America/New_York.

 **Be aware that AWS machines are often initially setup with UTC as the timezone instead of Eastern.**

3. Install Media Cloud on the machine.

5. Install the Media Cloud API Python client from https://github.com/c4fcm/MediaCloud-API-Client

5. cd to the Media Cloud installation directory

6. Import media and feeds from the production server by running `python python_scripts/media_import.py --api-key API-KEY` where API-KEY is an API key for mediacloud.org.

7. Start supvisisor by running `./supervisor/supervisord.sh`

8. Optional: Stop the extractor workers by running `./supervisor/supervisorctl.sh stop extract_and_vector`

9. Let the crawler on this machine run as long as desired.

# Exporting

When you're ready to export:

1. Stop the crawler by running `./supervisor/supervisorctl.sh stop mc:crawler`

2. Start the mediacloud server by running `./script/run_server_with_carton.sh` and leave it running in its own terminal

3. Find the API key for the local Media Cloud user by running `./script/run_with_carton.sh ./script/mediawords_manage_users.pl  --action=show --email=jdoe@mediacloud.org`

4. Export feed_downloads to the production system by running. `python python_scripts/export_feed_downloads_through_api.py --source-api-key SOURCE_API_KEY --dest-api-key DEST_API_KEY --source-media-cloud-api_url SOURCE_MEDIA_CLOUD_API_URL --dest-media-cloud-api_url DEST_MEDIA_CLOUD_API_URL`

 Where SOURCE_API_KEY is the local API key found above, DEST_API_KEY is an API key on the Media Cloud server to which you are exporting, SOURCE_MEDIA_CLOUD_API_URL is the base URL of the local server from which you are exporting downloads (this will almost always be 'http://localhost:3000/'), and DEST_MEDIA_CLOUD_API_URL is the base URL of the server to which you are exporting downloads (this will almost always be 'https://api.mediacloud.org/')

 E.g.

 `python python_scripts/export_feed_downloads_through_api.py --source-api-key 'e07cf98dd0d457351354ee520635c226acd238ecf15ec9e853346e185343bf7b' --dest-api-key  '1161251f5de4f381a198eea4dc20350fd992f5eef7cb2fdc284c245ff3d4f3ca' --source-media-cloud-api_url  'http://localhost:3000/' --dest-media-cloud-api_url https://api.mediacloud.org/

5. Verify that this script completed successfully by examining the output.
