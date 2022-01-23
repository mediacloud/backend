#
# Mine topic worker
#

FROM gcr.io/mcback/topics-base:latest

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/topics-mine/
ENV PYTHONPATH="/opt/mediacloud/src/topics-mine/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_mine_worker.py"]
