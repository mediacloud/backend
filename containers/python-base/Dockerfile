#
# Python code base
#

FROM dockermediacloud/mediacloud-base:latest

RUN \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get -y --no-install-recommends install \
        build-essential \
        python3.7 \
        python3.7-dev \
    && \
    curl https://bootstrap.pypa.io/get-pip.py | sudo -H python3.7 && \
    rm -rf /root/.cache/ && \
    true

