svn up > /dev/null
svn status | grep '^M' && echo "Unchecked in changes aborting" && exit
./script/mediawords_reformat_all_code.sh
svn commit -m "Auto formatting fix script"
