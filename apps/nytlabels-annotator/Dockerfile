#
# NYT-based news tagger service
#

FROM dockermediacloud/base:latest

RUN \
    #
    # Install model fetch dependencies
    apt-get -y --no-install-recommends install \
        brotli \
        libhdf5-103 \
    && \
    #
    # Create directory for annotator
    mkdir -p /usr/src/crappy-predict-news-labels/models/ && \
    #
    true

# Download and extract models
# (get them first so that every code change doesn't trigger huge model redownload)
WORKDIR /usr/src/crappy-predict-news-labels/models/
ENV MODEL_URL="https://mediacloud-nytlabels-data.s3.amazonaws.com/predict-news-labels-keyedvectors"
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/GoogleNews-vectors-negative300.keyedvectors.bin.br" | \
        brotli -d > GoogleNews-vectors-negative300.keyedvectors.bin
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/GoogleNews-vectors-negative300.keyedvectors.bin.vectors.npy.br" | \
        brotli -d > GoogleNews-vectors-negative300.keyedvectors.bin.vectors.npy
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/all_descriptors.hdf5.br" | \
        brotli -d > all_descriptors.hdf5
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/descriptors_3000.hdf5.br" | \
        brotli -d > descriptors_3000.hdf5
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/descriptors_600.hdf5.br" | \
        brotli -d > descriptors_600.hdf5
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/descriptors_with_taxonomies.hdf5.br" | \
        brotli -d > descriptors_with_taxonomies.hdf5
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/just_taxonomies.hdf5.br" | \
        brotli -d > just_taxonomies.hdf5

# Install Python 3.7
# (we need TensorFlow 1.x, and that version of the module doesn't support
# Python 3.8: https://github.com/tensorflow/tensorflow/issues/34302)
RUN \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys F23C5A6CF475977595C89F51BA6932366A755776 && \
    echo "deb http://ppa.launchpad.net/deadsnakes/ppa/ubuntu focal main" > /etc/apt/sources.list.d/deadsnakes.list && \
    apt-get update && \
    apt-get -y --no-install-recommends install \
        build-essential \
        python3.7 \
        python3.7-dev \
    && \
    #
    # We don't install Python 3.5 via APT's "python3" package but want to make
    # Python 3.7 be available via "python3" binary
    ln -s /usr/bin/python3.7 /usr/bin/python3 && \
    ln -s /usr/lib/python3.7/ /usr/lib/python3/ && \
    #
    # Install Pip
    curl https://bootstrap.pypa.io/get-pip.py | sudo -H python3.7 && \
    rm -rf /root/.cache/ && \
    true

# Install Python module dependencies
RUN \
    apt-get -y --no-install-recommends install \
        #
        # scipy seems to be looking for Fortran compiler, no idea why
        gfortran \
        libblas-dev \
        liblapack-dev \
    && \
    #
    true

# Install requirements
# (do this first so that minor changes in the annotator's code don't trigger a full module reinstall)
WORKDIR /usr/src/crappy-predict-news-labels/
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

# Set PYTHONPATH and PATH so that PyCharm is able to resolve dependencies
ENV PYTHONPATH="/usr/src/crappy-predict-news-labels:${PYTHONPATH}" \
    PATH="/usr/src/crappy-predict-news-labels:${PATH}"

# Tagger port
EXPOSE 8080

# We can just kill -9 the thing
STOPSIGNAL SIGTERM

USER nobody

CMD ["nytlabels_http_server.py"]
