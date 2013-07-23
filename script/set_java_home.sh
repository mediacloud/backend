#!/bin/bash
#
# Try to guess path to where Java is installed and set the Bash variable accordingly
#

if [ `uname` == 'Darwin' ]; then

    # Mac OS X
    JAVA_HOME=/System/Library/Frameworks/JavaVM.framework/

    if     [ ! -d $JAVA_HOME ] \
        || [ ! -f $JAVA_HOME/Commands/javac ] \
        || [ ! -f $JAVA_HOME/Headers/jni.h ] \
        || [ ! -f $JAVA_HOME/Libraries/libjvm.dylib ]; then

        echo "Proper Java deployment was not found in $JAVA_HOME."
        echo "Please download and install Java for OS X Developer Package from"
        echo "https://developer.apple.com/downloads/ or via the Software Update."
        exit 1
    fi

else

    # Assume Ubuntu
    JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64/

fi
