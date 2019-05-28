#
# NYT-based news tagger service
#

FROM dockermediacloud/mediacloud-base:latest

# Copy source
RUN mkdir -p /usr/src/
COPY src/MediaCloud-NYT-News-Labeler/ /usr/src/predict-news-labels/

# Install tagger
RUN \
    #
    # Install Python 2.7 (Python 3 not yet supported by the service)
    apt-get -y --no-install-recommends install \
        build-essential \
        libhdf5-10 \
        python2.7 \
        python2.7-dev \
        python-pip \
        python-setuptools \
        unzip \
    && \
    pip2 install --upgrade pip && \
    #
    # Install Python modules
    pip2 install -r /usr/src/predict-news-labels/requirements.txt && \
    #
    # Cleanup to save some disk space
    apt-get -y remove \
        build-essential \
        python2.7-dev \
        python-pip \
        # Don't uninstall python-setuptools because gunicorn uses it
        # Don't uninstall unzip because it will be needed for unextracting models
    && \
    apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /root/.cache/ && \
    true

# Install NLTK data
RUN \
    python2 -m nltk.downloader -d /usr/local/share/nltk_data punkt && \
    rm /usr/local/share/nltk_data/tokenizers/punkt.zip && \
    true

# Install models
RUN \
    mkdir -p /usr/src/predict-news-labels/word2vec-GoogleNews-vectors/ && \
    python2 /usr/src/predict-news-labels/download_models.py && \
    true

# Tagger port
EXPOSE 80

# Run tagger
COPY bin/predict_news_labels.sh /

CMD ["/predict_news_labels.sh"]
