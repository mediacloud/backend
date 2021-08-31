#
# Base image for apps that use Java
#

FROM gcr.io/mcback/base:latest

ENV JAVA_HOME=/usr/lib/jvm/java-16-amazon-corretto/

# Install OpenJDK 16 with Docker support improvements:
#
# * https://bugs.openjdk.java.net/browse/JDK-8146115
# * https://github.com/corretto/corretto-jdk/releases
#
RUN \
    apt-get -y --no-install-recommends install p11-kit && \
    /dl_to_stdout.sh "https://corretto.aws/downloads/resources/16.0.2.7.1/java-16-amazon-corretto-jdk_16.0.2.7-1_$(dpkg --print-architecture).deb" > /var/tmp/corretto.deb && \
    apt-get -y --no-install-recommends install /var/tmp/corretto.deb && \
    rm /var/tmp/corretto.deb && \
    #
    # Remove source code
    #
    find "$JAVA_HOME" -name src.zip -delete && \
    #
    # https://github.com/docker-library/openjdk/issues/331#issuecomment-498834472
    #
    find "$JAVA_HOME/lib" -name '*.so' -exec dirname '{}' ';' | \
        sort -u > /etc/ld.so.conf.d/docker-openjdk.conf && \
    ldconfig && \
    #
    # https://github.com/docker-library/openjdk/issues/212#issuecomment-420979840
    # https://openjdk.java.net/jeps/341
    java -Xshare:dump && \
    #
    true

# Use cgroup's memory / CPU limits
ENV JDK_JAVA_OPTIONS="-XX:+UseContainerSupport"

# Install our own security profile
COPY mediacloud-java.security /
ENV JDK_JAVA_OPTIONS="$JDK_JAVA_OPTIONS -Djava.security.properties=/mediacloud-java.security"

# Add script that will keep system and Java certificates up-to-date and in sync
COPY docker-openjdk.update.d.sh /etc/ca-certificates/update.d/openjdk
RUN \
    chmod +x /etc/ca-certificates/update.d/openjdk && \
    /etc/ca-certificates/update.d/openjdk

# Test if Java is working
RUN \
    echo 'public class Main { public static void main(String[] args) { System.out.println("Java works!"); } }' > /var/tmp/Main.java && \
    javac /var/tmp/Main.java && \
    java -classpath /var/tmp/ Main && \
    rm /var/tmp/Main.* && \
    true
