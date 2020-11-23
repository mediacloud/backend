#
# Base image for apps that use Java
#

FROM dockermediacloud/base:latest

ENV JAVA_HOME=/usr/lib/jvm/java-14-openjdk-amd64/

# Install prerequisites
RUN apt-get -y --no-install-recommends install binutils fontconfig libfreetype6 p11-kit

# Install OpenJDK 14 with Docker support improvements:
#
# * https://bugs.openjdk.java.net/browse/JDK-8146115
# * https://jdk.java.net/14/
#
RUN \
    #
    # Download and install OpenJDK 12 with Docker support improvements:
    #
    # * https://bugs.openjdk.java.net/browse/JDK-8146115
    # * https://jdk.java.net/12/
    #
    mkdir -p "${JAVA_HOME}" && \
    curl --fail --location --retry 3 --retry-delay 5 "https://download.java.net/java/GA/jdk14.0.1/664493ef4a6946b186ff29eb326336a2/7/GPL/openjdk-14.0.1_linux-x64_bin.tar.gz" | \
        tar -zx -C "${JAVA_HOME}" --strip 1 && \
    update-alternatives --install /usr/bin/java java "${JAVA_HOME}/bin/java" 1 && \
    update-alternatives --install /usr/bin/javac javac "${JAVA_HOME}/bin/javac" 1 && \
    #
    # Remove source code
    #
    rm "${JAVA_HOME}/lib/src.zip" && \
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
