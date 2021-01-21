#
# NYT-based news tagger service
#

FROM dockermediacloud/base:latest

RUN \
    #
    # Install model fetch dependencies
    apt-get -y --no-install-recommends install \
        brotli \
    && \
    #
    # Create directory for annotator
    mkdir -p /usr/src/crappy-predict-news-labels/models/ && \
    #
    true

# Download and extract models
# (get them first so that every code change doesn't trigger huge model redownload)
WORKDIR /usr/src/crappy-predict-news-labels/models/
ENV MODEL_URL="https://mediacloud-nytlabels-data.s3.amazonaws.com/predict-news-labels-onnx"

RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/GoogleNews-vectors-negative300.keyedvectors.br" | \
        brotli -d > GoogleNews-vectors-negative300.keyedvectors
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/GoogleNews-vectors-negative300.keyedvectors.vectors.npy.br" | \
        brotli -d > GoogleNews-vectors-negative300.keyedvectors.vectors.npy

RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/scaler.onnx" > scaler.onnx

RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/all_descriptors.onnx.br" | \
        brotli -d > all_descriptors.onnx
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/all_descriptors.txt.br" | \
        brotli -d > all_descriptors.txt

RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/descriptors_3000.onnx.br" | \
        brotli -d > descriptors_3000.onnx
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/descriptors_3000.txt.br" | \
        brotli -d > descriptors_3000.txt

RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/descriptors_600.onnx.br" | \
        brotli -d > descriptors_600.onnx
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/descriptors_600.txt.br" | \
        brotli -d > descriptors_600.txt

RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/descriptors_with_taxonomies.onnx.br" | \
        brotli -d > descriptors_with_taxonomies.onnx
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/descriptors_with_taxonomies.txt.br" | \
        brotli -d > descriptors_with_taxonomies.txt

RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/just_taxonomies.onnx.br" | \
        brotli -d > just_taxonomies.onnx
RUN curl --fail --location --retry 3 --retry-delay 5 "$MODEL_URL/just_taxonomies.txt.br" | \
        brotli -d > just_taxonomies.txt

# Install Python
RUN \
    apt-get -y --no-install-recommends install \
        python3 \
        python3-dev \
        python3-pip \
    && \
    true

# Install requirements
# (do this first so that minor changes in the annotator's code don't trigger a
# full module reinstall)
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
