#
# Base image for apps that use Java
#

FROM dockermediacloud/base:latest

ENV JAVA_HOME /usr/lib/jvm/java-12-openjdk-amd64/

RUN \
    #
    # Download and install OpenJDK 12 with Docker support improvements:
    #
    # * https://bugs.openjdk.java.net/browse/JDK-8146115
    # * https://jdk.java.net/12/
    #
    mkdir -p "${JAVA_HOME}" && \
    curl --fail --location --retry 3 --retry-delay 5 "https://download.java.net/java/GA/jdk12.0.2/e482c34c86bd4bf8b56c0b35558996b9/10/GPL/openjdk-12.0.2_linux-x64_bin.tar.gz" | \
        tar -zx -C "${JAVA_HOME}" --strip 1 && \
    update-alternatives --install /usr/bin/java java "${JAVA_HOME}/bin/java" 1 && \
    update-alternatives --install /usr/bin/javac javac "${JAVA_HOME}/bin/javac" 1 && \
    #
    # Remove unused stuff
    # (https://github.com/Docker-Hub-frolvlad/docker-alpine-java/blob/master/Dockerfile)
    #
    rm -rf \
        "${JAVA_HOME}/"*src.zip \
        "${JAVA_HOME}/lib/missioncontrol" \
        "${JAVA_HOME}/lib/visualvm" \
        "${JAVA_HOME}/lib/"*javafx* \
        "${JAVA_HOME}/jre/lib/plugin.jar" \
        "${JAVA_HOME}/jre/lib/ext/jfxrt.jar" \
        "${JAVA_HOME}/jre/bin/javaws" \
        "${JAVA_HOME}/jre/lib/javaws.jar" \
        "${JAVA_HOME}/jre/lib/desktop" \
        "${JAVA_HOME}/jre/plugin" \
        "${JAVA_HOME}/jre/lib/"deploy* \
        "${JAVA_HOME}/jre/lib/"*javafx* \
        "${JAVA_HOME}/jre/lib/"*jfx* \
        "${JAVA_HOME}/jre/lib/amd64/libdecora_sse.so" \
        "${JAVA_HOME}/jre/lib/amd64/"libprism_*.so \
        "${JAVA_HOME}/jre/lib/amd64/libfxplugins.so" \
        "${JAVA_HOME}/jre/lib/amd64/libglass.so" \
        "${JAVA_HOME}/jre/lib/amd64/libgstreamer-lite.so" \
        "${JAVA_HOME}/jre/lib/amd64/"libjavafx*.so \
        "${JAVA_HOME}/jre/lib/amd64/"libjfx*.so \
        "${JAVA_HOME}/jre/bin/jjs" \
        # "${JAVA_HOME}/jre/bin/keytool" \
        "${JAVA_HOME}/jre/bin/orbd" \
        "${JAVA_HOME}/jre/bin/pack200" \
        "${JAVA_HOME}/jre/bin/policytool" \
        "${JAVA_HOME}/jre/bin/rmid" \
        "${JAVA_HOME}/jre/bin/rmiregistry" \
        "${JAVA_HOME}/jre/bin/servertool" \
        "${JAVA_HOME}/jre/bin/tnameserv" \
        "${JAVA_HOME}/jre/bin/unpack200" \
        "${JAVA_HOME}/jre/lib/ext/nashorn.jar" \
        "${JAVA_HOME}/jre/lib/jfr.jar" \
        "${JAVA_HOME}/jre/lib/jfr" \
        "${JAVA_HOME}/jre/lib/oblique-fonts" \
    && \
    #
    # https://github.com/docker-library/openjdk/issues/212#issuecomment-420979840
    # https://openjdk.java.net/jeps/341
    java -Xshare:dump && \
    #
    true

# Install our own security profile
COPY mediacloud-java.security /
ENV JDK_JAVA_OPTIONS="$JDK_JAVA_OPTIONS -Djava.security.properties=/mediacloud-java.security"

# Test if Java is still working after all the cleanup
RUN \
    echo 'public class Main { public static void main(String[] args) { System.out.println("Java works!"); } }' > /var/tmp/Main.java && \
    javac /var/tmp/Main.java && \
    java -classpath /var/tmp/ Main && \
    rm /var/tmp/Main.* && \
    true
