#
# NYT-based news tagger service
#

FROM dockermediacloud/base:latest

# Install Python 2.7 (Python 3 not yet supported by the service)
RUN \
    # FIXME don't update APT every time
    apt-get -y update && \
    apt-get -y --no-install-recommends install \
        brotli \
        build-essential \
        libhdf5-10 \
        python2.7 \
        python2.7-dev \
        python-pip \
        python-setuptools \
    && \
    pip2 install --upgrade pip && \
    true

# Install Python modules
COPY src/MediaCloud-NYT-News-Labeler/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip2 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Install NLTK data
RUN \
    python2 -m nltk.downloader -d /usr/local/share/nltk_data punkt && \
    rm /usr/local/share/nltk_data/tokenizers/punkt.zip && \
    true

# Copy source
RUN mkdir -p /usr/src/
COPY src/MediaCloud-NYT-News-Labeler/ /usr/src/predict-news-labels/

# Install models
RUN \
    mkdir -p /usr/src/predict-news-labels/word2vec-GoogleNews-vectors/ && \
    python2 /usr/src/predict-news-labels/download_models.py && \
    true

# Tagger port
EXPOSE 8080

# Docker Swarm manages worker count
ENV WORKERS 1

WORKDIR /usr/src/predict-news-labels/

USER nobody

CMD ["/usr/local/bin/gunicorn", "-b", ":8080", "-t", "900", "--preload", "app:app"]
