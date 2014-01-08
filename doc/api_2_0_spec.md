% Media Cloud API Version 2
% Author David Larochelle
% December 13, 2013

#API URLs

## Media

### api/v2/media/single/

URL                                    Function
---------------------------------      ------------------------------------------------------------
api/v2/media/single/\<media_id\>         Return the media source in which media_id equals \<media_id\>
---------------------------------      ------------------------------------------------------------

####Query Parameters 

None.

####Example
Fetching Information on the New York Times

URL: http://0.0.0.0:3000/api/v2/media/single/1

Response:

```json
[
  {
    "is_not_dup": null,
    "feeds_added": 1,
    "sw_data_end_date": null,
    "moderated": 1,
    "media_source_tags": [
      {
        "tag_set": "media_type",
        "tags_id": 1,
        "tag": "newspapers",
        "tag_sets_id": 1
      },
      {
        "tag": "3",
        "tags_id": 109,
        "tag_set": "usnewspapercirculation",
        "tag_sets_id": 3
      },
      {
        "tag_set": "word_cloud",
        "tags_id": 6071565,
        "tag": "include",
        "tag_sets_id": 17
      },
      {
        "tag_set": "word_cloud",
        "tag": "default",
        "tags_id": 6729599,
        "tag_sets_id": 17
      },
      {
        "tag_sets_id": 5,
        "tags_id": 8874930,
        "tag": "adplanner_english_news_20090910",
        "tag_set": "collection"
      },
      {
        "tag_set": "collection",
        "tag": "ap_english_us_top25_20100110",
        "tags_id": 8875027,
        "tag_sets_id": 5
      }
    ],
    "unpaged_stories": 119,
    "foreign_rss_links": 0,
    "sw_data_start_date": null,
    "extract_author": 1,
    "name": "New York Times",
    "media_id": 1,
    "url": "http:\/\/nytimes.com",
    "full_text_rss": null,
    "media_sets": [
      {
        "media_sets_id": 24,
        "name": "New York Times",
        "set_type": "medium",
        "description": null
      }
    ],
    "dup_media_id": null,
    "moderation_notes": null,
    "use_pager": 0
  }
]
```


### api/v2/media/list/

URL                                                                       Function
---------------------------------      -------------------------------------------
api/v2/media/list                      Return multiple media sources 
---------------------------------      -------------------------------------------

####Query Parameters 

--------------------------------------------------------------------------------------------------------
Parameter         Default         Notes
---------------   ----------      ----------------------------------------------------------------------
 last_media_id    0               return media sources with a 
                                  media_id is greater than this value

 rows             20              Number of media sources to return. Cannot be larger than 100
--------------------------------------------------------------------------------------------------------

####Example -- TDB


## Media Sets

###api/v2/media_set/single

URL                                      Function
---------------------------------        ------------------------------------------------------------
api/v2/media_set/single/\<media_sets_id\>         Return the media source in which media_sets_id equals \<media_sets_id\>
---------------------------------        ------------------------------------------------------------

####Query Parameters 

None.

####Example

http://0.0.0.0:5000/api/v2/media_sets/single/2

```json
{
   'name': 'set name'
   'media_sets_id': 2
   'media': [
      	    {       'name': 'source 1 name',
	            'media_id': 'source 1 media id',
		    'url': 'http://source1.com'
            },
      	    {       'name': 'source 2 name',
	            'media_id': 'source 2 media id',
		    'url': 'http://source2.com'
            },
	    ]
}
```
###api/v2/media/list

URL                                                                       Function
---------------------------------      -------------------------------------------
api/v2/media/list                      Return multiple media sources 
---------------------------------      -------------------------------------------

####Query Parameters 

--------------------------------------------------------------------------------------------------------
Parameter             Default         Notes
-------------------   ----------      ----------------------------------------------------------------------
 last_media_sets_id    0               return media sets with 
                                       media_sets_id is greater than this value

 rows                  20              Number of media sets to return. Can not be larger than 100
--------------------------------------------------------------------------------------------------------

####Example




## Stories

### api/v2/stories/single

URL                                    Function
------------------------------------   ------------------------------------------------------------
api/v2/stories/single/\<stories_id\>     Return story in which stories_id equals \<stories_id\>
------------------------------------   ------------------------------------------------------------

####Query Parameters 

--------------------------------------------------------------------------------------------------------
Parameter             Default         Notes
-------------------   ----------      ----------------------------------------------------------------------
 raw_1st_download     0                If non-zero include the full html of the first page of the story
--------------------------------------------------------------------------------------------------------

####Example

Note: This fetches data on the Global Voices Story [Myanmar's new flag and new name](http://globalvoicesonline.org/2010/10/26/myanmars-new-flag-and-new-name/#comment-1733161) CC licensed story from November 2010.

http://0.0.0.0:5000/api/v2/stories/stories_query/27456565


```json
[
  {
    "story_text": " \t\t\t\t\t\tMyanmar's new flag and new name\t\t    The new flag, designated in the 2008 Constitution, has a central star set against a yellow, green and red background.   The old flags will be lowered by government department officials who were born on a Tuesday, while the new flags will be raised by officials born on a Wednesday.   One million flags have been made by textile factories, according to sources within the Ministry of Defence.    The green color of the flag officially represents peace, yellow solidarity, and red valour. Myanmar also has a new name: It is now officially known as the Republic of the Union of Myanmar. It was previously known as the Union of Myanmar.   What are the reactions of Myanmar netizens?  dawn_1o9  doesn\u2019t like the new flag    Just received news that our country's flag has changed officially. And I say this here, and I say it loud: I DON'T LIKE THE NEW FLAG!!!   I feel no patriotism when I see this. And the color scheme is the same as Lithuanian flag minus the star, though the hue is different.   I am not the only one who feels like this though. Many are outraged. Personally, I feel like it is an insult.   \u201clooks like a cheap amateurish crap that came out from MS Paint\u201d - my friend's words: not mine.   This is the old flag. Blue stands for peace and stability, red stands for courage and bravery, 14 stars for the 14 states and divisions, the pinion stands for the work force of the country, and the rice stalk stands for the farmers in the country. I love this flag, and it will always be the flag of my country, no matter how much they change it    An interesting conversation in her blog about the topic     awoolham:  Yellow stands for than shwe (author\u2019s note: the leader of Myanmar), green stands for cash, red stands for blood of the people.    ei_angel:  What the!!\u2026They can't change it yet.  Man I hate that flag. Looks like Ethiopian flag or Ghana flag.  So the name has changed to RUM (Republic of the Union of MM) too?  I thought it would only be changed after all the 7 step has taken place.  And that's after the parliament's been called.      dawn_1o9:  @cafengocmy - It looks like a lot of African nation's flags too. With the flag before, Taiwan was the only country whose flag looked like ours. Now, it's about 3 or 4 flags: Ghana, Ethiopia, Lithuania, etc.   The commenter\u2019s reaction about the premature unveiling of the flag was the same sentiment of the opposition. The flag is supposed to be released only after the conduct of the November 7 elections. The opposition accuses the Myanmar military leaders of violating their own constitution.  Min Lwin  of the  Democratic Voice of Burma  adds more information     According to opposition politicians, Burmese law states that the 2008 constitution must come into force before any new flag is raised. This shouldn\u2019t happen until after the controversial 7 November elections.     All the old flags will be burnt. My guess is, the government is so anti-American that even having the same colors, albeit having socialist ideals, isn't going to work.   And in a couple of weeks, we will be voting. Some of us, for the first time in our lives. I voted two years ago at the consulate in Kolkata for the new constitution, in my late 20s, after growing up mostly in democratic countries.   Who will win? The government of course. Now that they're all civilians \u2014 emperors in new clothes, with their new flag. They're going to have the country, too, one way or another. No matter what the people say, do, or think let alone the rest of the world. It doesn't matter what I write here or what you comment, tweet, or who you share this with.    At the comment section of  The Irrawaddy , the conversation continues about the new flag  The new flag is look like exactly the same as the Shan State flag apart from the star instead of white circle inside.  What a shame Than Shwe copied another flag.  Clever move by the junta. It'll look great on T-shirts if tourism ever takes off, and who can really be angry with laid-back rastafarians?  But is the Irrawaddy going to recognise it? Or will \u201cBurma\u201d retain its flag as it fights to stay afloat in the march of history?    Indre : I'm sorry, but why did the government snatch Lithuania's national flag (yellow, green and red) and crossed it so curiously with Vietnam's (star in the center)?    Chindits:  This flag does not represent the country at all. A star?? You know That big white star is also the only star on the colors of Myanmar's tatmadaw, navy, air force and police force. This flag represent only the armed forces.  ",
    "guid": "http:\/\/globalvoicesonline.org\/?p=169660#comment-1733161",
    "publish_date": "2010-11-24 04:05:00",
    "media_id": 1144,
    "stories_id": 27456565,
    "story_texts_id": null,
    "story_sentences": [
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "Myanmar's new flag and new name The new flag, designated in the 2008 Constitution, has a central star set against a yellow, green and red background.",
        "sentence_number": 0,
        "story_sentences_id": "525687757",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "sentence_number": 1,
        "story_sentences_id": "525687758",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "language": null,
        "db_row_last_updated": null,
        "sentence": "The old flags will be lowered by government department officials who were born on a Tuesday, while the new flags will be raised by officials born on a Wednesday."
      },
      {
        "sentence": "One million flags have been made by textile factories, according to sources within the Ministry of Defence.",
        "db_row_last_updated": null,
        "language": null,
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144,
        "story_sentences_id": "525687759",
        "sentence_number": 2
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "The green color of the flag officially represents peace, yellow solidarity, and red valour.",
        "sentence_number": 3,
        "story_sentences_id": "525687760",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "Myanmar also has a new name: It is now officially known as the Republic of the Union of Myanmar.",
        "story_sentences_id": "525687761",
        "sentence_number": 4,
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "It was previously known as the Union of Myanmar.",
        "sentence_number": 5,
        "story_sentences_id": "525687762",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "story_sentences_id": "525687763",
        "sentence_number": 6,
        "db_row_last_updated": null,
        "sentence": "What are the reactions of Myanmar netizens?",
        "language": null
      },
      {
        "db_row_last_updated": null,
        "sentence": "dawn_1o9 doesn\u2019t like the new flag Just received news that our country's flag has changed officially.",
        "language": null,
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 7,
        "story_sentences_id": "525687764"
      },
      {
        "language": null,
        "sentence": "And I say this here, and I say it loud: I DON'T LIKE THE NEW FLAG!!!",
        "db_row_last_updated": null,
        "story_sentences_id": "525687765",
        "sentence_number": 8,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565
      },
      {
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 9,
        "story_sentences_id": "525687766",
        "sentence": "I feel no patriotism when I see this.",
        "db_row_last_updated": null,
        "language": null
      },
      {
        "sentence_number": 10,
        "story_sentences_id": "525687767",
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00",
        "language": null,
        "db_row_last_updated": null,
        "sentence": "And the color scheme is the same as Lithuanian flag minus the star, though the hue is different."
      },
      {
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 11,
        "story_sentences_id": "525687768",
        "sentence": "I am not the only one who feels like this though.",
        "db_row_last_updated": null,
        "language": null
      },
      {
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "story_sentences_id": "525687769",
        "sentence_number": 12,
        "db_row_last_updated": null,
        "sentence": "Many are outraged.",
        "language": null
      },
      {
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144,
        "story_sentences_id": "525687770",
        "sentence_number": 13,
        "db_row_last_updated": null,
        "sentence": "Personally, I feel like it is an insult.",
        "language": null
      },
      {
        "sentence_number": 14,
        "story_sentences_id": "525687771",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "language": null,
        "db_row_last_updated": null,
        "sentence": "\u201clooks like a cheap amateurish crap that came out from MS Paint\u201d - my friend's words: not mine."
      },
      {
        "sentence_number": 15,
        "story_sentences_id": "525687772",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "language": null,
        "db_row_last_updated": null,
        "sentence": "This is the old flag."
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "Blue stands for peace and stability, red stands for courage and bravery, 14 stars for the 14 states and divisions, the pinion stands for the work force of the country, and the rice stalk stands for the farmers in the country.",
        "sentence_number": 16,
        "story_sentences_id": "525687773",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "I love this flag, and it will always be the flag of my country, no matter how much they change it An interesting conversation in her blog about the topic awoolham: Yellow stands for than shwe (author\u2019s note: the leader of Myanmar), green stands for cash, red stands for blood of the people.",
        "sentence_number": 17,
        "story_sentences_id": "525687774",
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 18,
        "story_sentences_id": "525687775",
        "sentence": "ei_angel: What the!!\u2026They can't change it yet.",
        "db_row_last_updated": null,
        "language": null
      },
      {
        "language": null,
        "sentence": "Man I hate that flag.",
        "db_row_last_updated": null,
        "sentence_number": 19,
        "story_sentences_id": "525687776",
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "sentence": "Looks like Ethiopian flag or Ghana flag.",
        "db_row_last_updated": null,
        "language": null,
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 20,
        "story_sentences_id": "525687777"
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "So the name has changed to RUM (Republic of the Union of MM) too?",
        "story_sentences_id": "525687778",
        "sentence_number": 21,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565
      },
      {
        "story_sentences_id": "525687779",
        "sentence_number": 22,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "language": null,
        "sentence": "I thought it would only be changed after all the 7 step has taken place.",
        "db_row_last_updated": null
      },
      {
        "story_sentences_id": "525687780",
        "sentence_number": 23,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "language": null,
        "db_row_last_updated": null,
        "sentence": "And that's after the parliament's been called."
      },
      {
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 24,
        "story_sentences_id": "525687781",
        "db_row_last_updated": null,
        "sentence": "dawn_1o9: @cafengocmy - It looks like a lot of African nation's flags too.",
        "language": null
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "With the flag before, Taiwan was the only country whose flag looked like ours.",
        "story_sentences_id": "525687782",
        "sentence_number": 25,
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144
      },
      {
        "language": null,
        "sentence": "Now, it's about 3 or 4 flags: Ghana, Ethiopia, Lithuania, etc. The commenter\u2019s reaction about the premature unveiling of the flag was the same sentiment of the opposition.",
        "db_row_last_updated": null,
        "sentence_number": 26,
        "story_sentences_id": "525687783",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144,
        "story_sentences_id": "525687784",
        "sentence_number": 27,
        "db_row_last_updated": null,
        "sentence": "The flag is supposed to be released only after the conduct of the November 7 elections.",
        "language": null
      },
      {
        "story_sentences_id": "525687785",
        "sentence_number": 28,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "language": null,
        "sentence": "The opposition accuses the Myanmar military leaders of violating their own constitution.",
        "db_row_last_updated": null
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "Min Lwin of the Democratic Voice of Burma adds more information According to opposition politicians, Burmese law states that the 2008 constitution must come into force before any new flag is raised.",
        "story_sentences_id": "525687786",
        "sentence_number": 29,
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144
      },
      {
        "db_row_last_updated": null,
        "sentence": "This shouldn\u2019t happen until after the controversial 7 November elections.",
        "language": null,
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 30,
        "story_sentences_id": "525687787"
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "All the old flags will be burnt.",
        "sentence_number": 31,
        "story_sentences_id": "525687788",
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "story_sentences_id": "525687789",
        "sentence_number": 32,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "language": null,
        "db_row_last_updated": null,
        "sentence": "My guess is, the government is so anti-American that even having the same colors, albeit having socialist ideals, isn't going to work."
      },
      {
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 33,
        "story_sentences_id": "525687790",
        "db_row_last_updated": null,
        "sentence": "And in a couple of weeks, we will be voting.",
        "language": null
      },
      {
        "language": null,
        "sentence": "Some of us, for the first time in our lives.",
        "db_row_last_updated": null,
        "story_sentences_id": "525687791",
        "sentence_number": 34,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565
      },
      {
        "story_sentences_id": "525687792",
        "sentence_number": 35,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "language": null,
        "db_row_last_updated": null,
        "sentence": "I voted two years ago at the consulate in Kolkata for the new constitution, in my late 20s, after growing up mostly in democratic countries."
      },
      {
        "story_sentences_id": "525687793",
        "sentence_number": 36,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "language": null,
        "sentence": "Who will win?",
        "db_row_last_updated": null
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "The government of course.",
        "story_sentences_id": "525687794",
        "sentence_number": 37,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565
      },
      {
        "language": null,
        "sentence": "Now that they're all civilians \u2014 emperors in new clothes, with their new flag.",
        "db_row_last_updated": null,
        "sentence_number": 38,
        "story_sentences_id": "525687795",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "language": null,
        "sentence": "They're going to have the country, too, one way or another.",
        "db_row_last_updated": null,
        "story_sentences_id": "525687796",
        "sentence_number": 39,
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144
      },
      {
        "sentence": "No matter what the people say, do, or think let alone the rest of the world.",
        "db_row_last_updated": null,
        "language": null,
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 40,
        "story_sentences_id": "525687797"
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "It doesn't matter what I write here or what you comment, tweet, or who you share this with.",
        "story_sentences_id": "525687798",
        "sentence_number": 41,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565
      },
      {
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 42,
        "story_sentences_id": "525687799",
        "db_row_last_updated": null,
        "sentence": "At the comment section of The Irrawaddy , the conversation continues about the new flag The new flag is look like exactly the same as the Shan State flag apart from the star instead of white circle inside.",
        "language": null
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "What a shame Than Shwe copied another flag.",
        "sentence_number": 43,
        "story_sentences_id": "525687800",
        "stories_id": 27456565,
        "media_id": 1144,
        "publish_date": "2010-11-24 04:05:00"
      },
      {
        "db_row_last_updated": null,
        "sentence": "Clever move by the junta.",
        "language": null,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "story_sentences_id": "525687801",
        "sentence_number": 44
      },
      {
        "db_row_last_updated": null,
        "sentence": "It'll look great on T-shirts if tourism ever takes off, and who can really be angry with laid-back rastafarians?",
        "language": null,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "story_sentences_id": "525687802",
        "sentence_number": 45
      },
      {
        "story_sentences_id": "525687803",
        "sentence_number": 46,
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144,
        "language": null,
        "db_row_last_updated": null,
        "sentence": "But is the Irrawaddy going to recognise it?"
      },
      {
        "sentence_number": 47,
        "story_sentences_id": "525687804",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "language": null,
        "db_row_last_updated": null,
        "sentence": "Or will \u201cBurma\u201d retain its flag as it fights to stay afloat in the march of history?"
      },
      {
        "db_row_last_updated": null,
        "sentence": "Indre : I'm sorry, but why did the government snatch Lithuania's national flag (yellow, green and red) and crossed it so curiously with Vietnam's (star in the center)?",
        "language": null,
        "publish_date": "2010-11-24 04:05:00",
        "media_id": 1144,
        "stories_id": 27456565,
        "story_sentences_id": "525687805",
        "sentence_number": 48
      },
      {
        "story_sentences_id": "525687806",
        "sentence_number": 49,
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144,
        "language": null,
        "db_row_last_updated": null,
        "sentence": "Chindits: This flag does not represent the country at all."
      },
      {
        "sentence_number": 50,
        "story_sentences_id": "525687807",
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "language": null,
        "sentence": "A star??",
        "db_row_last_updated": null
      },
      {
        "language": null,
        "db_row_last_updated": null,
        "sentence": "You know That big white star is also the only star on the colors of Myanmar's tatmadaw, navy, air force and police force.",
        "story_sentences_id": "525687808",
        "sentence_number": 51,
        "publish_date": "2010-11-24 04:05:00",
        "stories_id": 27456565,
        "media_id": 1144
      },
      {
        "media_id": 1144,
        "stories_id": 27456565,
        "publish_date": "2010-11-24 04:05:00",
        "sentence_number": 52,
        "story_sentences_id": "525687809",
        "db_row_last_updated": null,
        "sentence": "This flag represent only the armed forces.",
        "language": null
      }
    ],
    "db_row_last_updated": null,
    "story_tags": [
      
    ],
    "full_text_rss": 0,
    "description": "<p>Both the previously current and now current Burmese flags look ugly and ridiculous!  Burma once had a flag that was actually better looking.  Also Taiwan&#8217;s flag needs to change!  it is a party state flag representing the republic of china since 1911 and Taiwan\/Formosa was Japanese colony since 1895.  A new flag representing the land, people and history of Taiwan needs to be given birth to and flown!<\/p>\n",
    "language": null,
    "title": "Comment on Myanmar's new flag and new name by kc",
    "fully_extracted": 1,
    "collect_date": "2010-11-24 15:33:39",
    "url": "http:\/\/globalvoicesonline.org\/2010\/10\/26\/myanmars-new-flag-and-new-name\/comment-page-1\/#comment-1733161"
  }
]
```

###api/V2/stories/list_processed 
  
To get information on multiple stories send get requests to `api/V2/stories/list_processed`


URL                                                                       Function
---------------------------------      -------------------------------------------
api/V2/stories/list_processed           Return multiple processed stories
---------------------------------      -------------------------------------------

####Query Parameters 

--------------------------------------------------------------------------------------------------------
Parameter                     Default         Notes
---------------------------   ----------      ----------------------------------------------------------
 last_processed_stories_id    0               return stories in which the processed_stories_id 
                                                is greater than this value

 rows                         20              Number of stories to return. Can not be larger than 100

 raw_1st_download             0               If non-zero include the full html of the first
                                              page of the story
--------------------------------------------------------------------------------------------------------
  
The ‘last_processed_id’ parameter can be used to page through these results. The api will return 20 stories with a processed_id greater than this value.

NOTE: stories_id and processed_id are separate values. The order in which stories are processed is different than the story_id order. The processing pipeline involves downloading, extracting, and vectoring stories. Since unprocessed stories are of little interest, we have introduced the processed_id field to allow users to stream all stories as they’re processed.

####Example -TBD

## Story subsets

These who want to only see a subset of stories can create a story subset stream by sending a put request to `api/v2/stories/subset/?data=\<JSON\> `where \<JSON_STRING\> is a URL encoded JSON representation of the story subset.

###api/v2/stories/subset

URL                                                                       Function
---------------------------------      --------------------------------------------------
api/v2/stories/subset                    Creates a story subset. Must use a PUT request
---------------------------------      --------------------------------------------------

####Query Parameters 

--------------------------------------------------------------------------------------------------------
Parameter                     Notes
---------------------------   --------------------------------------------------------------------------
 start_date                   Only include stories with a publish date \>= start_date

 end_date                     Only include stories with a publish date \<= end_date


 media_id                     Only include stories from the media source indicated by media_id

 media_sets_id                Only include stories from the media set indicated by media_sets_id
--------------------------------------------------------------------------------------------------------

*_Note:_* At least one of the above paramters must by provided.

The put request will return the meta-data representation of the `story_subset` including its database ID.
  
It will take the backend system a while to generate the stream of stories for the newly created subset. There is a background daemon script (`mediawords_process_story_subsets.pl`) that detects newly created subsets and adds stories to them.

####Example -- TBD

URL                                                                       Function
---------------------------------      --------------------------------------------------
api/v2/stories/subset                    show the status of a subset. Must use a GET request
---------------------------------      --------------------------------------------------

  
To see the status of a given subset, the client sends a get request to `api/v2/stories/subset/<ID>` where `<ID>` is the database id that was returned in the put request above.  The returned object contains a `'ready'` field with a boolean value indicating that stories from the subset have been compiled.
  
###api/V2/stories/list_subset_processed

URL                                                                       Function
--------------------------------------------  ------------------------------------------------
api/V2/stories/list_subset_processed/\<id\>     Return multiple processed stories
                                                from a subset. \<id\> is the id of the subset
--------------------------------------------  ------------------------------------------------

####Query Parameters

--------------------------------------------------------------------------------------------------------
Parameter                     Default         Notes
---------------------------   ----------      ----------------------------------------------------------
 last_processed_stories_id    0               return stories in which the processed_stories_id 
                                                is greater than this value

 rows                         20              Number of stories to return. Can not be larger than 100

 raw_1st_download             0               If non-zero include the full html of the first
                                              page of the story
--------------------------------------------------------------------------------------------------------
 
  
This behaves similarly to the `list_processed` URL above except only stories from the given subset are returned.

####Example -- TBD

##Solr

###query/sentences

####TDB

###query/wc

####TDB

# Output Format / JSON
  
The format of the API responses is determine by the ‘Accept’ header on the request. The default is ‘application/json’. Other supported formats include 'text/html', 'text/x-json', and  'text/x-php-serialization'. It’s recommended that you explicitly set the ‘Accept’ header rather than relying on the default.

  
Here’s an example of setting the ‘Accept’ header in Python

```python  
import pkg_resources  

import requests   
assert pkg_resources.get_distribution("requests").version >= '1.2.3'
 
r = requests.get( 'http://amanda.law.harvard.edu/admin/api/stories/all_processed?page=1', auth=('mediacloud-admin', KEY), headers = { 'Accept': 'application/json'})  

data = r.json()
```


# Code examples

##Create a CSV file with all media sources.

```python
media = []
start = 0
rows  = 100
while True:
      params = { 'start': start, 'rows': rows }
      print "start:{} rows:{}".format( start, rows)
      r = requests.get( 'http://localhost:5000/api/v2/media/list', params = params, headers = { 'Accept': 'application/json'} )
      data = r.json()

      if len(data) == 0:
      	 break

      start += rows
      media.extend( data )

fieldnames = [ 
 u'media_id',
 u'url',
 u'moderated',
 u'moderation_notes',
 u'name'
 ]

with open( '/tmp/media.csv', 'wb') as csvfile:
    print "open"
    cwriter = csv.DictWriter( csvfile, fieldnames, extrasaction='ignore')
    cwriter.writeheader()
    cwriter.writerows( media )

```

