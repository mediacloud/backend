#
# CLIFF annotator service
#

FROM dockermediacloud/java-base:latest

ENV PATH="/usr/lib/maven/bin:/usr/lib/tomcat7/bin:${PATH}" \
    #
    # Annotator requires some more RAM
    JAVA_OPTS="-Xmx4096m"

# Download and extract CLAVIN's geonames index
RUN \
    mkdir -p /etc/cliff2/IndexDirectory/ && \
    /dl_to_stdout.sh "https://github.com/mediacloud/clavin-build-geonames-index/releases/download/2020-11-25/IndexDirectory.tar.gz" | \
        tar -zx -C /etc/cliff2/IndexDirectory/ --strip 1 && \
    true

# Install Maven for building CLIFF
# (can't use APT because we didn't install Java through it)
RUN \
    mkdir -p /usr/lib/maven/ && \
    /dl_to_stdout.sh "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.6.2/apache-maven-3.6.2-bin.tar.gz" | \
        tar -zx -C /usr/lib/maven/ --strip 1 && \
    true

# Install Tomcat 7
RUN \
    mkdir -p /usr/lib/tomcat7/ && \
    /dl_to_stdout.sh "https://archive.apache.org/dist/tomcat/tomcat-7/v7.0.96/bin/apache-tomcat-7.0.96.tar.gz" | \
        tar -zx -C /usr/lib/tomcat7/ --strip 1 && \
    true

# Copy source
RUN mkdir -p /usr/src/
COPY src/ /usr/src/

# Build CLIFF
RUN \
    #
    # Test if submodules were checked out
    if [ ! -f /usr/src/CLIFF/LICENSE ]; then \
        echo && \
        echo "Git submodules haven't been checked out, please run:" && \
        echo && \
        echo "    git submodule update --init --recursive" && \
        echo && \
        echo "and then rebuild this container." && \
        echo && \
        exit 1; \
    fi && \
    #
    # Test if the builder machine has enough RAM
    if [ $(/container_memory_limit.sh) -le 3900 ]; then \
        echo && \
        echo "The builder machine needs at least 4 GB of RAM to run CLIFF" && \
        echo "annotator tests. Please increase RAM available to Docker or" && \
        echo "try rebuilding on a bigger machine." && \
        echo && \
        exit 1; \
    fi && \
    #
    # Build CLIFF
    cd /usr/src/CLIFF/ && \
    mvn package && \
    #
    # Copy exploded WAR to Tomcat 7's webroot
    mv webapp/target/cliff-2.6.1/ /usr/lib/tomcat7/webapps/cliff/ && \
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

# Expose Tomcat 7's port
EXPOSE 8080

# Change to non-privileged user
USER www-data

# Run Tomcat 7
CMD ["catalina.sh", "run"]
