#
# NYT-Based News Tagger service
#

FROM mediacloud-base:latest

# Install Python 2.7 (Python 3 not yet supported by the service)
RUN \
    apt-get -y --no-install-recommends install \
        build-essential \
        python2.7 \
        python2.7-dev \
        python-pip \
        python-setuptools \
    && \
    pip2 install --upgrade pip && \
    rm -rf /root/.cache/ && \
    true

# Copy source
RUN mkdir -p /usr/src/
COPY src/predict-news-labels/ /usr/src/predict-news-labels/

# Install Python modules
RUN \
    pip2 install -r /usr/src/predict-news-labels/requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Install NLTK data
RUN python2 -m nltk.downloader -d /usr/local/share/nltk_data punkt

# Install models
RUN python2 /usr/src/predict-news-labels/download_models.py

# Tagger port
EXPOSE 8080

# Run tagger
COPY bin/predict-news-labels.sh /
CMD ["/predict-news-labels.sh"]
