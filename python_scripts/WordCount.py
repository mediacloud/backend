#!/usr/bin/python
import re
# this one in honor of 4th July, or pick text file you have!!!!!!!
filename = 'out.txt'
# create list of lower case words, \s+ --> match any whitespace(s)
# you can replace file(filename).read() with given string
word_list = re.split('\s+', file(filename).read().lower())
print 'Words in text:', len(word_list)
# create dictionary of word:frequency pairs
freq_dic = {}
# punctuation marks to be removed
punctuation = re.compile(r'[.?!,":;]') 
for word in word_list:
    # remove punctuation marks
    word = punctuation.sub("", word)
    # form dictionary
    try: 
        freq_dic[word] += 1
    except: 
        freq_dic[word] = 1

print 'Unique words:', len(freq_dic)
# create list of (key, val) tuple pairs
freq_list = freq_dic.items()
# sort by key or word
freq_list.sort()
# display result
for word, freq in freq_list:
    print word, freq
