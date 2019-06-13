# Running Docker remotely

Docker is split up into client and daemon parts, and Docker CLI talks to its daemon using HTTP REST. This means that Docker daemon doesn't have to necessarily run on your own development machine. You should consider running Docker daemon remotely if:

* You do development on a computer with limited CPU, RAM and disk space resources;
* You work on a project that requires rebuilding a lot of container images;
* You do development on an OS that isn't Linux, e.g. macOS or Windows;
* You have a slow internet connection so image rebuilds which fetch heavy resources take a long time.

Precise instructions on how to set up a remote Docker daemon are beyond the scope of this document because it's OS-dependent, but to run Docker daemon remotely you might want to:

1. Set up a remote Ubuntu machine with a fast internet connection (e.g. EC2 instance);

2. Install Docker on said remote Ubuntu machine using Ansible provisioning script;

3. Make Docker [daemon listen to `tcp://127.0.0.1:2376`](https://success.docker.com/article/how-do-i-enable-the-remote-api-for-dockerd) (make sure to not listen to `0.0.0.0` as that would make Docker daemon listen publicly) and restart Docker daemon;

4. Stop and disable development machine's Docker daemon instance if one is running;

5. Configure SSH to forward remote port 2376 to local port 2376:

   ```
   # ~/.ssh/config
   Host mc_remote_docker
       HostName <...>
       User ubuntu
       IdentityFile ~/.ssh/<...>.pem
   
       # Docker
       LocalForward 2376 127.0.0.1:2376
   ```

6. SSH into the remote Ubuntu machine with [autossh](https://www.harding.motd.ca/autossh/) to make sure that the connection doesn't time out due to inactivity:

   ```bash
   $ autossh -M 0 -f -T -N mc_remote_docker
   ```

7. Docker CLI utility (`docker`) should be able to connect to the remote machine automatically now. If it doesn't, make sure that your `DOCKER_HOST` environment variable is either empty or set to `tcp://127.0.0.1:2376`.

8. To make PyCharm's remote debugger work with a remote Docker daemon:

   1. Forward an additional port from a remote Ubuntu machine to your own computer:

      ```
      Host mc_remote_docker
          # <...>
      
          # PyCharm remote debugger
          LocalForward 12345 127.0.0.1:12345
      ```

   2. Configure PyCharm [to use the newly forwarded port](https://www.jetbrains.com/help/pycharm/remote-debugging-with-product.html#remote-debug-config).

9. To be able to use volumes on a remote Docker daemon so that the containers in Compose's test environment get auto-updated with local source code changes without having to rebuild container images, you'll have to mount your local directory with Media Cloud's source code to the remote machine. Here's a way to do that with Samba (CIFS):

   1. On your development computer, share the source code directory using Samba. For example, on macOS you'd have to enable *File Sharing*, add the Media Cloud's source code directory to the list of *Shared Folders*, and enable both *Share files and folders using SMB* and *Windows File Sharing* under *Options…*;

   2. On your development computer, add three extra *local* (as opposed to remote) port forwards to forward local Samba (CIFS) ports to the remote Ubuntu host:

      ```
      Host mc_remote_docker
          # <...>
      
      
          # SMB
          RemoteForward 127.0.0.1:10137 127.0.0.1:137
          RemoteForward 127.0.0.1:10138 127.0.0.1:138
          RemoteForward 127.0.0.1:10139 127.0.0.1:139
          RemoteForward 127.0.0.1:10445 127.0.0.1:445
      ```

   3. On the Ubuntu host with the remote Docker daemon, mount the Samba (CIFS) share from your local computer:

      ```bash
      $ sudo apt-get -y install cifs-utils
      
      $ mkdir /home/ubuntu/mediacloud/
      
      # Quite untested really, some more fancy options might be neccessary:
      $ sudo mount -v -t cifs \
          -o "username=user,password=xxx,port=10445" \
          "//127.0.0.1/mediacloud" \
          /home/ubuntu/mediacloud
      ```

   4. After mounting the local Media Cloud source directory to a remote Ubuntu machine with Docker daemon running, you should be able to run developer scripts (e.g. `run.py`) on said machine and have the source code auto-updated on Compose environment's test containers.

You might try setting up remote Docker instance [using Docker Machine](https://www.kevinkuszyk.com/2016/11/28/connect-your-docker-client-to-a-remote-docker-host/) as well.
