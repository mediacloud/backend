tail -n +2 russian_stopwords-comments.txt  | perl -E 'while(<>) {split; say $_[0] unless($_[2]  || ! $_[0]);} ' > russian_stopwords.txt 
