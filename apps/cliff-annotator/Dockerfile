#
# CLIFF annotator service
#

FROM dockermediacloud/base:latest

# Download and extract CLAVIN's geonames index
RUN \
    mkdir -p /etc/cliff2/IndexDirectory/ && \
    curl -L "https://github.com/berkmancenter/mediacloud-clavin-build-geonames-index/releases/download/2019-09-06/IndexDirectory.tar.gz" \
        > /var/tmp/clavin-geonames-index.tar.gz && \
    tar -zxf /var/tmp/clavin-geonames-index.tar.gz -C /etc/cliff2/IndexDirectory/ --strip 1 && \
    rm /var/tmp/clavin-geonames-index.tar.gz && \
    true

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

# Install Maven for building CLIFF
# (can't use APT because we didn't install Java through it)
RUN \
    mkdir -p /usr/lib/maven/ && \
    curl -L "http://mirror.cogentco.com/pub/apache/maven/maven-3/3.6.2/binaries/apache-maven-3.6.2-bin.tar.gz" \
        > /var/tmp/maven.tar.gz && \
    tar -zxf /var/tmp/maven.tar.gz -C /usr/lib/maven/ --strip 1 && \
    rm /var/tmp/maven.tar.gz && \
    true
ENV PATH="/usr/lib/maven/bin:${PATH}"

# Install Tomcat 7
RUN \
    mkdir -p /usr/lib/tomcat7/ && \
    curl -L "http://mirror.cogentco.com/pub/apache/tomcat/tomcat-7/v7.0.96/bin/apache-tomcat-7.0.96.tar.gz" \
        > /var/tmp/tomcat7.tar.gz && \
    tar -zxf /var/tmp/tomcat7.tar.gz -C /usr/lib/tomcat7/ --strip 1 && \
    rm /var/tmp/tomcat7.tar.gz && \
    true
ENV PATH="/usr/lib/tomcat7/bin:${PATH}"

# Copy source
RUN mkdir -p /usr/src/
COPY src/ /usr/src/

# Test if submodules were checked out
RUN \
    if [ ! -f /usr/src/CLIFF/LICENSE ]; then \
        echo && \
        echo "Git submodules haven't been checked out, please run:" && \
        echo && \
        echo "    git submodule update --init --recursive" && \
        echo && \
        echo "and then rebuild this container." && \
        echo && \
        exit 1; \
    fi

# Build CLIFF
RUN \
    cd /usr/src/CLIFF/ && \
    mvn package && \
    #
    # Copy exploded WAR to Tomcat 7's webroot
    mv webapp/target/cliff-2.4.2/ /usr/lib/tomcat7/webapps/cliff/ && \
    #
    # Cleanup
    mvn clean && \
    rm -rf ~/.m2/ && \
    true

# Configure Tomcat 7
RUN \
    #
    # Copy configuration
    mv /usr/src/tomcat7/conf/logging.properties /usr/lib/tomcat7/conf/logging.properties && \
    mv /usr/src/tomcat7/conf/server.xml /usr/lib/tomcat7/conf/server.xml && \
    rm -rf /usr/src/tomcat7/ && \
    #
    # No secrets in configuration
    chmod 644 /usr/lib/tomcat7/conf/* && \
    #
    # Some extra directories that seem to be needed
    mkdir -p /usr/lib/tomcat7/conf/Catalina/localhost/ && \
    chown -R www-data:www-data /usr/lib/tomcat7/conf/Catalina/localhost/ && \
    mkdir -p /usr/lib/tomcat7/work/Catalina/localhost/ && \
    chown -R www-data:www-data /usr/lib/tomcat7/work/Catalina/localhost/ && \
    true

# Install Python 2 for running mock HTTP server
# FIXME remove
RUN apt-get -y --no-install-recommends install python-minimal

# Copy mock HTTP server
# FIXME remove
COPY bin/mock_cliff_annotator.py /

# Expose Tomcat 7's port
EXPOSE 8080

# Change to non-privileged user
USER www-data

# Annotator requires some more RAM
ENV JAVA_OPTS "-Xmx4096m"

# Run Tomcat 7
# FIXME uncomment
# CMD ["catalina.sh", "run"]

# Run mock HTTP server
# FIXME remove
CMD ["/mock_cliff_annotator.py"]
