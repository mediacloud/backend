#
# Base image for Nginx
#

FROM gcr.io/mcback/base:latest

# Install packages
RUN \
    #
    # Install newest Nginx
    curl -L https://nginx.org/keys/nginx_signing.key | apt-key add - && \
    echo "deb https://nginx.org/packages/mainline/ubuntu/ focal nginx" > /etc/apt/sources.list.d/nginx.list && \
    echo "deb-src https://nginx.org/packages/mainline/ubuntu/ focal nginx" > /etc/apt/sources.list.d/nginx.list && \
    apt-get -y update && \
    apt-get -y --no-install-recommends install nginx && \
    true

# Replace configuration with our own
RUN \
    rm -rf \
        /etc/nginx/fastcgi.conf \
        /etc/nginx/nginx.conf \
        /etc/nginx/conf.d/ \
        /etc/nginx/sites-available/ \
        /etc/nginx/sites-enabled/ \
        /etc/nginx/snippets/ \
        && \
    true
COPY nginx/nginx.conf nginx/include/ /etc/nginx/
