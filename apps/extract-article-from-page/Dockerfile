#
# HTTP service that extracts article HTML from a page HTML
#
# FIXME possibly add cache
#

FROM dockermediacloud/common:latest

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/extract-article-from-page/
ENV PERL5LIB="/opt/mediacloud/src/extract-article-from-page/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/extract-article-from-page/python:${PYTHONPATH}"

COPY bin /opt/mediacloud/bin

EXPOSE 8080

USER mediacloud

CMD ["extract_article_from_page_http_server.py", "--port", "8080"]
