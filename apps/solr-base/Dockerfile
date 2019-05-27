#
# Solr base
#

FROM dockermediacloud/mediacloud-base:latest

# Solr version
ENV MEDIACLOUD_SOLR_VERSION "6.5.0"

# Install OpenJDK 12 with Docker support improvements:
#
# * https://bugs.openjdk.java.net/browse/JDK-8146115
# * https://jdk.java.net/12/
#
RUN \
    mkdir -p /usr/lib/jvm/java-12-openjdk-amd64/ && \
    curl -L "https://download.java.net/java/GA/jdk12.0.1/69cfe15208a647278a19ef0990eea691/12/GPL/openjdk-12.0.1_linux-x64_bin.tar.gz" \
        > /var/tmp/openjdk.tar.gz && \
    tar -zxf /var/tmp/openjdk.tar.gz -C /usr/lib/jvm/java-12-openjdk-amd64/ --strip 1 && \
    rm /var/tmp/openjdk.tar.gz && \
    update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-12-openjdk-amd64/bin/java 1 && \
    update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/java-12-openjdk-amd64/bin/javac 1 && \
    true
ENV JAVA_HOME /usr/lib/jvm/java-12-openjdk-amd64/

# Download and extract Solr
RUN \
    curl -L "https://archive.apache.org/dist/lucene/solr/${MEDIACLOUD_SOLR_VERSION}/solr-${MEDIACLOUD_SOLR_VERSION}.tgz" \
        > /var/tmp/solr.tgz && \
    mkdir -p /opt/solr/ && \
    tar -zxf /var/tmp/solr.tgz -C /opt/solr --strip 1 && \
    rm /var/tmp/solr.tgz

# Copy Solr configuration
RUN mkdir -p /usr/src/
COPY src/solr/ /usr/src/solr/
