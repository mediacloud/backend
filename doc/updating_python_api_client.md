# Updating Python API client

To update Media Cloud Python API client from upstream:

1. Fetch a fork repository of the API client:

        git clone https://github.com/dlarochelle/MediaCloud-API-Client.git

2. Add upstream repository as one of the "remotes":

        git remote add upstream https://github.com/c4fcm/MediaCloud-API-Client.git
        git fetch upstream

3. Merge upstream's changes over fork:

        git merge upstream/master

4. Push the changes to fork's remote:

        git push
