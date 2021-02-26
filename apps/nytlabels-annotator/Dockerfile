#
# NYT-based news tagger service
#

FROM gcr.io/mcback/base:latest

RUN \
    # FIXME remove once the base image gets updated
    apt-get -y update && \
    #
    # Install model fetch dependencies
    apt-get -y --no-install-recommends install brotli && \
    #
    # Create directory for annotator
    mkdir -p /usr/src/crappy-predict-news-labels/models/ && \
    #
    true

# Download and extract models
# (get them first so that every code change doesn't trigger huge model redownload)
WORKDIR /usr/src/crappy-predict-news-labels/models/
ENV MODEL_URL="https://mediacloud-nytlabels-data.s3.amazonaws.com/predict-news-labels-onnx"

RUN /dl_to_stdout.sh "$MODEL_URL/GoogleNews-vectors-negative300.stripped.shelve.br" | \
        brotli -d > GoogleNews-vectors-negative300.stripped.shelve

RUN /dl_to_stdout.sh "$MODEL_URL/scaler.onnx" > scaler.onnx

RUN /dl_to_stdout.sh "$MODEL_URL/all_descriptors.onnx.br" | \
        brotli -d > allDescriptors.onnx
RUN /dl_to_stdout.sh "$MODEL_URL/all_descriptors.txt.br" | \
        brotli -d > allDescriptors.txt

RUN /dl_to_stdout.sh "$MODEL_URL/descriptors_3000.onnx.br" | \
        brotli -d > descriptors3000.onnx
RUN /dl_to_stdout.sh "$MODEL_URL/descriptors_3000.txt.br" | \
        brotli -d > descriptors3000.txt

RUN /dl_to_stdout.sh "$MODEL_URL/descriptors_600.onnx.br" | \
        brotli -d > descriptors600.onnx
RUN /dl_to_stdout.sh "$MODEL_URL/descriptors_600.txt.br" | \
        brotli -d > descriptors600.txt

RUN /dl_to_stdout.sh "$MODEL_URL/descriptors_with_taxonomies.onnx.br" | \
        brotli -d > descriptorsAndTaxonomies.onnx
RUN /dl_to_stdout.sh "$MODEL_URL/descriptors_with_taxonomies.txt.br" | \
        brotli -d > descriptorsAndTaxonomies.txt

RUN /dl_to_stdout.sh "$MODEL_URL/just_taxonomies.onnx.br" | \
        brotli -d > taxonomies.onnx
RUN /dl_to_stdout.sh "$MODEL_URL/just_taxonomies.txt.br" | \
        brotli -d > taxonomies.txt

# Install NLTK data
RUN \
    apt-get -y --no-install-recommends install unzip && \
    mkdir -p /usr/local/share/nltk_data/tokenizers/punkt/PY3/ && \
    /dl_to_stdout.sh "https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/tokenizers/punkt.zip" \
        > /var/tmp/punkt.zip && \
    cd /var/tmp/ && \
    unzip punkt.zip && \
    rm punkt.zip && \
    cd /var/tmp/punkt/ && \
    cp english.pickle /usr/local/share/nltk_data/tokenizers/punkt/ && \
    cp PY3/english.pickle /usr/local/share/nltk_data/tokenizers/punkt/PY3/ && \
    cd / && \
    rm -rf /var/tmp/punkt/ && \
    apt-get -y remove unzip && \
    true

# Install Python
RUN \
    apt-get -y --no-install-recommends install \
        python3 \
        python3-dev \
        python3-pip \
        #
        # Needed by "shelve" module:
        python3-gdbm \
    && \
    true

# Install requirements
# (do this first so that minor changes in the annotator's code don't trigger a
# full module reinstall)
WORKDIR /usr/src/crappy-predict-news-labels/
COPY src/crappy-predict-news-labels/requirements.txt /usr/src/crappy-predict-news-labels/
RUN \
    #
    # OpenMP for onnxruntime speed up
    apt-get -y --no-install-recommends install libgomp1 && \
    #
    # The rest
    pip3 install -r requirements.txt && \
    rm -rf /root/.cache/ && \
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

CMD ["nytlabels.sh"]
