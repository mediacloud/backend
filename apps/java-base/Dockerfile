#
# Base image for apps that use Java
#

FROM dockermediacloud/base:latest

# Install OpenJDK 12 with Docker support improvements:
#
# * https://bugs.openjdk.java.net/browse/JDK-8146115
# * https://jdk.java.net/12/
#
RUN \
    mkdir -p /usr/lib/jvm/java-12-openjdk-amd64/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://download.java.net/java/GA/jdk12.0.2/e482c34c86bd4bf8b56c0b35558996b9/10/GPL/openjdk-12.0.2_linux-x64_bin.tar.gz" | \
        tar -zx -C /usr/lib/jvm/java-12-openjdk-amd64/ --strip 1 && \
    update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-12-openjdk-amd64/bin/java 1 && \
    update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/java-12-openjdk-amd64/bin/javac 1 && \
    #
    # https://github.com/docker-library/openjdk/issues/212#issuecomment-420979840
    # https://openjdk.java.net/jeps/341
    java -Xshare:dump && \
    #
    true

ENV JAVA_HOME /usr/lib/jvm/java-12-openjdk-amd64/

# Install our own security profile
COPY mediacloud-java.security /
ENV JDK_JAVA_OPTIONS="$JDK_JAVA_OPTIONS -Djava.security.properties=/mediacloud-java.security"
