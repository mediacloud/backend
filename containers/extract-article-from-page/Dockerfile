#
# HTTP service that extracts article HTML from a page HTML
#
# FIXME possibly add cache
#

FROM dockermediacloud/mediacloud-common:latest

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

COPY bin/extract_article_from_page.py /

EXPOSE 80

CMD ["/extract_article_from_page.py", "--port", "80"]
