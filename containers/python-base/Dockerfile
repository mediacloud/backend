#
# Python code base
#

FROM mediacloud-base:latest

# Install Python
RUN \
    apt-get -y --no-install-recommends install \
        build-essential \
        python3 \
        python3-dev \
        python3-pip \
        python3-setuptools \
    && \
    true

# Upgrade Pip
RUN \
    pip3 install --upgrade pip && \
    rm -rf /root/.cache/ && \
    true
