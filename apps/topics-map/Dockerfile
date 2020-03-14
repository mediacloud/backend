#
# map topic worker
#

FROM dockermediacloud/common:latest


# install wget
RUN  apt-get -y install wget

# install fa2l java libs
RUN \
	mkdir /opt/fa2l && \
	cd /opt/fa2l && \
	wget --quiet 'https://github.com/klarman-cell-observatory/forceatlas2/releases/download/1.0.3/forceatlas2.jar' && \
	wget --quiet 'https://github.com/klarman-cell-observatory/forceatlas2/releases/download/1.0.3/gephi-toolkit-0.9.2-all.jar' && \
	true

# install java 
RUN  apt-get -y install openjdk-8-jre-headless

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

CMD ["topics_map_worker.pl"]
