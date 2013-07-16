#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

if pwd | grep ' ' ; then
    echo "Media Cloud cannot be installed in a file path with spaces in its name"
    exit 1
fi

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

# Install the rest of the modules
JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install --deployment

echo "Successfully installed Perl and modules for MediaCloud"
