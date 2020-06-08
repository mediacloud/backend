#
# Base image for apps that use Java
#

FROM dockermediacloud/base:latest

# Install OpenJDK 14 with Docker support improvements:
#
# * https://bugs.openjdk.java.net/browse/JDK-8146115
# * https://jdk.java.net/14/
#
RUN \
    mkdir -p /usr/lib/jvm/java-14-openjdk-amd64/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://download.java.net/java/GA/jdk14.0.1/664493ef4a6946b186ff29eb326336a2/7/GPL/openjdk-14.0.1_linux-x64_bin.tar.gz" | \
        tar -zx -C /usr/lib/jvm/java-14-openjdk-amd64/ --strip 1 && \
    update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-14-openjdk-amd64/bin/java 1 && \
    update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/java-14-openjdk-amd64/bin/javac 1 && \
    #
    # https://github.com/docker-library/openjdk/issues/212#issuecomment-420979840
    # https://openjdk.java.net/jeps/341
    java -Xshare:dump && \
    #
    true

ENV JAVA_HOME /usr/lib/jvm/java-14-openjdk-amd64/
