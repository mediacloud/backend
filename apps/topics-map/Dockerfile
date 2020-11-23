#
# map topic worker
#

FROM dockermediacloud/common:latest

# Install Java
RUN apt-get update
RUN apt-get -y --no-install-recommends install openjdk-8-jre-headless

# Install fa2l Java libs
RUN \
    mkdir /opt/fa2l && \
    cd /opt/fa2l && \
    curl --fail --location --retry 3 --retry-delay 5 --output "forceatlas2.jar" \
        "https://github.com/klarman-cell-observatory/forceatlas2/releases/download/1.0.3/forceatlas2.jar" && \
    curl --fail --location --retry 3 --retry-delay 5 --output "gephi-toolkit.jar" \
        "https://github.com/klarman-cell-observatory/forceatlas2/releases/download/1.0.3/gephi-toolkit-0.9.2-all.jar" && \
    true

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/topics-map/
ENV PYTHONPATH="/opt/mediacloud/src/topics-map/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_map_worker_wrapper.sh"]
