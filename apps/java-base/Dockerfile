#
# Base image for apps that use Java
#

FROM gcr.io/mcback/base:latest

ENV JAVA_HOME /usr/lib/jvm/java-12-openjdk-amd64/

RUN \
    #
    # Download and install OpenJDK 12 with Docker support improvements:
    #
    # * https://bugs.openjdk.java.net/browse/JDK-8146115
    # * https://jdk.java.net/12/
    #
    mkdir -p "${JAVA_HOME}" && \
    /dl_to_stdout.sh "https://download.java.net/java/GA/jdk12.0.2/e482c34c86bd4bf8b56c0b35558996b9/10/GPL/openjdk-12.0.2_linux-x64_bin.tar.gz" | \
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

# Install our own security profile
COPY mediacloud-java.security /
ENV JDK_JAVA_OPTIONS="$JDK_JAVA_OPTIONS -Djava.security.properties=/mediacloud-java.security"

# Test if Java is still working
RUN \
    echo 'public class Main { public static void main(String[] args) { System.out.println("Java works!"); } }' > /var/tmp/Main.java && \
    javac /var/tmp/Main.java && \
    java -classpath /var/tmp/ Main && \
    rm /var/tmp/Main.* && \
    true
