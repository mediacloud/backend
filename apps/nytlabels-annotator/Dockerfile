#
# NYT-based news tagger service
#

FROM dockermediacloud/perl-python-base:latest

RUN \
    #
    # Install dependencies
    apt-get -y --no-install-recommends install \
        brotli \
        libhdf5-10 \
    && \
    #
    # Create directory for annotator
    mkdir -p /usr/src/crappy-predict-news-labels/models/ && \
    #
    true

WORKDIR /usr/src/crappy-predict-news-labels/

# Download models
# (get them first so that every code change doesn't trigger huge model redownload)
COPY src/crappy-predict-news-labels/download_models.py /usr/src/crappy-predict-news-labels/
RUN ./download_models.py

# Install requirements
# (do this first so that minor changes in the annotator's code don't trigger a full module reinstall)
COPY src/crappy-predict-news-labels/requirements.txt /usr/src/crappy-predict-news-labels/
RUN \
    pip3 install -r requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Install NLTK data
RUN \
    python3 -m nltk.downloader -d /usr/local/share/nltk_data punkt && \
    rm /usr/local/share/nltk_data/tokenizers/punkt.zip && \
    true

# Copy the rest of the source
COPY src/crappy-predict-news-labels/ /usr/src/crappy-predict-news-labels/

# Tagger port
EXPOSE 8080

# We can just kill -9 the thing
STOPSIGNAL SIGTERM

USER nobody

CMD ["./nytlabels_http_server.py"]
