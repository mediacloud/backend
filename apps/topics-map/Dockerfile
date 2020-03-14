#
# map topic worker
#

FROM dockermediacloud/common:latest

# install fa2l java libs
RUN \
	mkdir /opt/fa2l && \
	cd /opt/fa2l && \
	wget 'gephi-toolkit-0.9.2-all.jar' && \
	wget 'forceatlas2.jar' && \
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
ENV PYTHONPATH="/opt/mediacloud/src/topics-mine/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_map_worker.pl"]
