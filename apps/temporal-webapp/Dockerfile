#
# Temporal webapp
#

FROM mc2021/base:latest

RUN \
    #
    # Add NodeSource APT repository
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
    echo "deb https://deb.nodesource.com/node_14.x focal main" \
        > /etc/apt/sources.list.d/nodesource.list && \
    apt-get -y update && \
    #
    # Install Node.js
    apt-get -y --no-install-recommends install nodejs && \
    #
    true

# FIXME Vue.js still gets built in development mode
ENV NODE_ENV=production \
    NPM_CONFIG_PRODUCTION=true \
    TEMPORAL_GRPC_ENDPOINT=temporal-server:7233 \
    TEMPORAL_PERMIT_WRITE_API=true

RUN \
    #
    # Install build dependencies
    apt-get -y --no-install-recommends install git && \
    #
    # Create target directory
    mkdir -p /opt/temporal-webapp/ && \
    #
    # Download Temporal webapp
    # * We use Git instead of building a released package because we need
    #   the submodules for the build too;
    # * We check out a specific commit hash instead of a version tag to prevent
    #   dependency confusion
    #   (https://medium.com/@alex.birsan/dependency-confusion-4a5d60fec610);
    # * We do some extra trickery to do a shallow copy of just a single commit
    #   hash to save space + time (https://stackoverflow.com/a/43136160/200603);
    # * Submodule is referred to as a SSH URI, so we need to make Git's SSH
    #   work first too.
    #
    cd /opt/temporal-webapp/ && \
    git init && \
    git remote add origin https://github.com/temporalio/web.git && \
    # HEAD of "v1.9.0" tag:
    git fetch --depth 1 origin 6ed16d0dc07b4baf43e091028d98fa1fe7a29c06 && \
    git checkout FETCH_HEAD && \
    # SSH checkout doesn't work with the build container's public key not
    # registered with GitHub
    sed -i 's/git@github.com:/https:\/\/github.com\//g' .gitmodules && \
    git submodule init && \
    git submodule sync && \
    git submodule update --init --recursive --depth 1 && \
    #
    # Build the webapp
    npm install --production && \
    npm run build-production && \
    #
    # Remove build dependencies
    apt-get -y remove git && \
    apt-get -y autoremove && \
    apt-get -y clean && \
    #
    # Remove Git history as we won't need it
    rm -rf .git/ && \
    #
    # Add unprivileged user the service will run as
    useradd -ms /bin/bash temporal && \
    #
    true

WORKDIR /opt/temporal-webapp/

# Webapp port
EXPOSE 8088

USER temporal

CMD ["node", "server.js"]
