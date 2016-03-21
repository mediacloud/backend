#!/bin/bash
#
# Try to guess path to where Java is installed and set the Bash variable accordingly
#

if [ `uname` == 'Darwin' ]; then

    # Mac OS X
    declare -a POSSIBLE_JDK_PATHS=(
        /System/Library/Frameworks/JavaVM.framework/                        # OS X 10.8
        /Library/Java/JavaVirtualMachines/1.6.0_51-b11-457.jdk/Contents/    # OS X 10.9
    )

    for path in ${POSSIBLE_JDK_PATHS[@]}; do
        if     [[ -d "$path"
            &&    -f "$path/Commands/javac"
            &&    -f "$path/Headers/jni.h" 
            &&    -f "$path/Libraries/libjvm.dylib" ]]; then
            
            JAVA_HOME="$path"
            break
        fi
    done

    if [ -z "$JAVA_HOME" ]; then
        echo "Proper Java deployment was not found anywhere."
        echo "Please download and install Java for OS X Developer Package from"
        echo "https://developer.apple.com/downloads/ or via the Software Update."
        exit 1
    fi

else

    # Ubuntu
    declare -a POSSIBLE_JDK_PATHS=(
        /usr/lib/jvm/java-8-oracle/         # Oracle Java 8
        /usr/lib/jvm/java-7-openjdk-amd64/  # newer Ubuntu
        /usr/lib/jvm/java-6-sun             # older Ubuntu
    )

    for path in ${POSSIBLE_JDK_PATHS[@]}; do
        if     [[ -d "$path"
            &&    -f "$path/bin/javac"
            &&    -f "$path/include/jni.h" ]] ; then
            
            JAVA_HOME="$path"
	        break
        fi
    done

    if [ -z "$JAVA_HOME" ]; then
        echo "Proper Java deployment was not found anywhere."
        echo "Please download and install Java for OS X Developer Package by running:"
        echo "    apt-get install openjdk-7-jdk"
        exit 1
    fi

fi
