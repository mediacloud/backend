#
# Gradually move rows from unsharded tables to the sharded ones
#

FROM gcr.io/mcback/java-base:latest

# Add user that will be used for running userland apps
RUN useradd -ms /bin/bash mediacloud

# Install Maven for building the worker
# (can't use APT because we didn't install Java through it)
ENV PATH="/opt/move-rows-to-shards/bin:/usr/lib/maven/bin:${PATH}"
RUN \
    mkdir -p /usr/lib/maven/ && \
    /dl_to_stdout.sh "https://dlcdn.apache.org/maven/maven-3/3.8.4/binaries/apache-maven-3.8.4-bin.tar.gz" | \
        tar -zx -C /usr/lib/maven/ --strip 1 && \
    true

# Fetch plugins first to make source rebuilds faster
RUN mkdir /opt/move-rows-to-shards/
COPY pom.xml /opt/move-rows-to-shards/
WORKDIR /opt/move-rows-to-shards/
RUN mvn package

# Copy sources and build
COPY src/ /opt/move-rows-to-shards/src/
RUN \
    mvn package && \
    mv target/move-rows-to-shards-jar-with-dependencies.jar ./move-rows-to-shards.jar && \
    rm -rf target/ && \
    rm -rf ~/.m2/ && \
    true

COPY bin/ /opt/move-rows-to-shards/bin/

USER mediacloud

# Set a failing CMD because we'll be using the same image to run:
#
# * "workflow_worker.sh" - processes workflow;
# * "activities_worker.sh" - processes workflow's activities.
#
# so the user is expected to set "command" in docker-compose.yml to run a specific worker.
#
CMD ["SET_CONTAINER_COMMAND_TO_ONE_OF_THE_WORKERS"]
