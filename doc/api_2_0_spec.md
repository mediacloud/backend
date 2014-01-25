% Media Cloud API Version 2
% Author David Larochelle

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

URL: http://mediacloud.org/api/v2/media/single/1

Response:

```json
[
  {
    "url": "http:\/\/nytimes.com",
    "name": "New York Times",
    "media_id": 1,
    "media_source_tags": [
      {
        "tags_id": 1,
        "tag_sets_id": 1,
        "tag_set": "media_type",
        "tag": "newspapers"
      },
      {
        "tag_sets_id": 3,
        "tag_set": "usnewspapercirculation",
        "tag": "3",
        "tags_id": 109
      },
      {
        "tags_id": 6071565,
        "tag_sets_id": 17,
        "tag_set": "word_cloud",
        "tag": "include"
      },
      {
        "tag": "default",
        "tag_set": "word_cloud",
        "tag_sets_id": 17,
        "tags_id": 6729599
      },
      {
        "tag": "adplanner_english_news_20090910",
        "tag_set": "collection",
        "tag_sets_id": 5,
        "tags_id": 8874930
      },
      {
        "tag_sets_id": 5,
        "tag_set": "collection",
        "tag": "ap_english_us_top25_20100110",
        "tags_id": 8875027
      }
    ],
    "media_sets": [
      {
        "set_type": "medium",
        "media_sets_id": 24,
        "name": "New York Times",
        "description": null
      }
    ]
  }
]
```


###api/v2/media/list/

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

####Example

URL: http://mediacloud.org/api/v2/media/list?last_media_id=1&rows=2

```json
[
    "name": "Washington Post",
    "url": "http:\/\/washingtonpost.com",
    "media_id": 2,
  {
    "media_sets": [
      {
        "description": null,
        "name": "Washington Post",
        "media_sets_id": 18,
        "set_type": "medium"
      }
    ],
    "media_source_tags": [
      {
        "tags_id": 1,
        "tag": "newspapers",
        "tag_sets_id": 1,
        "tag_set": "media_type"
      },
      {
        "tag_set": "workflow",
        "tag_sets_id": 4,
        "tag": "pmcheck",
        "tags_id": 6
      },
      {
        "tag": "hrcheck",
        "tags_id": 7,
        "tag_set": "workflow",
        "tag_sets_id": 4
      },
      {
        "tag": "7",
        "tags_id": 18,
        "tag_set": "usnewspapercirculation",
        "tag_sets_id": 3
      },
      {
        "tags_id": 6071565,
        "tag": "include",
        "tag_set": "word_cloud",
        "tag_sets_id": 17
      },
      {
        "tag_sets_id": 17,
        "tag_set": "word_cloud",
        "tag": "default",
        "tags_id": 6729599
      },
      {
        "tags_id": 8875027,
        "tag": "ap_english_us_top25_20100110",
        "tag_set": "collection",
        "tag_sets_id": 5
      }
    ]
  },
  {
    "url": "http:\/\/csmonitor.com",
    "media_id": 3,
    "media_sets": [
      
    ],
    "name": "Christian Science Monitor",
    "media_source_tags": [
      {
        "tag_sets_id": 1,
        "tag_set": "media_type",
        "tags_id": 1,
        "tag": "newspapers"
      },
      {
        "tag": "needs",
        "tags_id": 110,
        "tag_sets_id": 4,
        "tag_set": "workflow"
      },
      {
        "tag_set": "workflow",
        "tag_sets_id": 4,
        "tags_id": 111,
        "tag": "collection"
      }
    ]
  }
]
```

## Media Sets

###api/v2/media_set/single

URL                                      Function
---------------------------------        ------------------------------------------------------------
api/v2/media_set/single/\<media_sets_id\>         Return the media set in which media_sets_id equals \<media_sets_id\>
---------------------------------        ------------------------------------------------------------

####Query Parameters 

None.

####Example

http://mediacloud.org/api/v2/media_sets/single/2

```json
[
   {
     "name": "set name"
     "media_sets_id": 2,
     "description": "media_set 2 description",
     "media": 
     [
      	    {       "name": "source 1 name",
	            "media_id": "source 1 media id",
		    "url": "http://source1.com"
            },
      	    {       "name": "source 2 name",
	            "media_id": "source 2 media id",
		    "url": "http://source2.com"
            },
     ]
   }
]
```

###api/v2/media_sets/list

URL                                                                       Function
---------------------------------      -------------------------------------------
api/v2/media_sets/list                      Return multiple media sets
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

URL: http://mediacloud.org/api/v2/media_sets/list?rows=1&last_media_sets_id=1

```json
[
   {
     "name": "set name",
     "media_sets_id": "2",
     "description": "media_set 2 description",
     "media": 
     [
      	    {       "name": "source 1 name",
	            "media_id": "source 1 media id",
		    "url": "http://source1.com"
            },
      	    {       "name": "source 2 name",
	            "media_id": "source 2 media id",
		    "url": "http://source2.com"
            },
     ]
   }
]
```
dddddd


## Feeds

###api/v2/feeds/single

URL                                      Function
---------------------------------        ------------------------------------------------------------
api/v2/feeds/single/\<feeds_id\>         Return the feeds in which feeds_id equals \<feeds_id\>
---------------------------------        ------------------------------------------------------------

####Query Parameters 

None.

####Example -TBD

http://mediacloud.org/api/v2/feeds/single/1

```json
[
  {
    "name": "Bits",
    "url": "http:\/\/bits.blogs.nytimes.com\/rss2.xml",
    "feeds_id": 1,
    "feed_type": "syndicated",
    "feed_status": "active",
    "media_id": 1
  }
]
```

###api/v2/feeds/list

URL                                                                       Function
---------------------------------      -------------------------------------------
api/v2/feeds/list                         Return multiple media sets
---------------------------------      -------------------------------------------

####Query Parameters 

--------------------------------------------------------------------------------------------------------
Parameter             Default         Notes
-------------------   ----------      ----------------------------------------------------------------------
 last_feeds_id         0               return feed with 
                                       feeds_id is greater than this value

 rows                  20              Number of feeds to return. Can not be larger than 100
--------------------------------------------------------------------------------------------------------

####Example

URL: http://mediacloud.org/api/v2/feeds/list?rows=1&last_feeds_id=1

```json
[
  {
    "name": "DealBook",
    "url": "http:\/\/dealbook.blogs.nytimes.com\/rss2.xml",
    "feeds_id": 2,
    "feed_type": "syndicated",
    "feed_status": "active",
    "media_id": 1
  },
  {
    "name": "Essential Knowledge of the Day",
    "url": "http:\/\/feeds.feedburner.com\/essentialknowledge",
    "feeds_id": 3,
    "feed_type": "syndicated",
    "feed_status": "active",
    "media_id": 1
  }
]
```

## Dashboards

###api/v2/dashboard/single

URL                                      Function
---------------------------------        ------------------------------------------------------------
api/v2/dashboard/single/\<dashboards_id\>         Return the dashboard in which dashboards_id equals \<dashboards_id\>
---------------------------------        ------------------------------------------------------------

####Query Parameters 

--------------------------------------------------------------------------------------------------------
Parameter             Default         Notes
-------------------   ----------      ----------------------------------------------------------------------
 nested_data             1               if 0 return only the name and dashboards_id otherwise 
                                         return nested information about the dashboard's media_sets 
                                         and their media
--------------------------------------------------------------------------------------------------------

####Example

http://mediacloud.org/api/v2/dashboards/single/2

```json
[
   {
      "name":"dashboard 2",
      "dashboards_id": "2",
      "media_sets":
      [
      {
         "name":"set name",
         "media_sets_id": "2",
         "media":[
            {
               "name":"source 1 name",
               "media_id":"source 1 media id",
               "url":"http://source1.com"
            },
            {
               "name":"source 2 name",
               "media_id":"source 2 media id",
               "url":"http://source2.com"
            },

         ]
      }
   ]
}
]
```

###api/v2/dashboards/list

URL                                                                       Function
---------------------------------      -------------------------------------------
api/v2/dashboards/list                      Return multiple dashboards
---------------------------------      -------------------------------------------

####Query Parameters 

--------------------------------------------------------------------------------------------------------
Parameter             Default         Notes
-------------------   ----------      ----------------------------------------------------------------------
 last_dashboards_id    0               return dashboards with 
                                       dashboards_id is greater than this value

 rows                  20              Number of dashboards to return. Can not be larger than 100

 nested_data             1             if 0 return only the name and dashboards_id otherwise 
                                       return nested information about the dashboard's media_sets 
                                       and their media
--------------------------------------------------------------------------------------------------------

####Example

URL: http://mediacloud.org/api/v2/dashboards/list?rows=1&last_dashboards_id=1

```json
[
   {
      "name":"dashboard 2",
      "dashboards_id":2,
      "media_sets":
      [
      {
         "name":"set name",
         "media_sets_id":2,
         "media":[
            {
               "name":"source 1 name",
               "media_id":"source 1 media id",
               "url":"http://source1.com"
            },
            {
               "name":"source 2 name",
               "media_id":"source 2 media id",
               "url":"http://source2.com"
            },

         ]
      }
   ]
}
] 
```

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

###Output description

--------------------------------------------------------------------------------------------------------
Field                    Description
-------------------      ----------------------------------------------------------------------
 title                    The story title as defined in the RSS feed. (May or may not contain
                           HTML depending on the source)

 description              The story description as defined in the RSS feed. (May or may not contain
                           HTML depending on the source)

 story_text

 story_sentences

 publish_date             The publish date of the story as specified in the RSS feed

 collect_date             The date the RSS feed was actually downloaded

 guid                     The GUID field in the RSS feed default to the URL if no GUID is specified?
 
--------------------------------------------------------------------------------------------------------



####Example

Note: This fetches data on the Global Voices Story [Myanmar's new flag and new name](http://globalvoicesonline.org/2010/10/26/myanmars-new-flag-and-new-name/#comment-1733161) CC licensed story from November 2010.

URL: http://mediacloud.org/api/v2/stories/single/27456565


```json
[
  {
    "db_row_last_updated": null,
    "full_text_rss": 0,
    "description": "<p>Both the previously current and now current Burmese flags look ugly and ridiculous!  Burma once had a flag that was actually better looking.  Also Taiwan&#8217;s flag needs to change!  it is a party state flag representing the republic of china since 1911 and Taiwan\/Formosa was Japanese colony since 1895.  A new flag representing the land, people and history of Taiwan needs to be given birth to and flown!<\/p>\n",
    "language": null,
    "title": "Comment on Myanmar's new flag and new name by kc",
    "fully_extracted": 1,
    "collect_date": "2010-11-24 15:33:39",
    "url": "http:\/\/globalvoicesonline.org\/2010\/10\/26\/myanmars-new-flag-and-new-name\/comment-page-1\/#comment-1733161",
    "guid": "http:\/\/globalvoicesonline.org\/?p=169660#comment-1733161",
    "publish_date": "2010-11-24 04:05:00",
    "media_id": 1144,
    "stories_id": 27456565,
    "story_texts_id": null,
    "story_text": " \t\t\t\t\t\tMyanmar's new flag and new name\t\t    The new flag, designated in the 2008 Constitution, has a central star set against a yellow, green and red background.   The old flags will be lowered by government department officials who were born on a Tuesday, while the new flags will be raised by officials born on a Wednesday.   One million flags have been made by textile factories, according to sources within the Ministry of Defence.    The green color of the flag officially represents peace, yellow solidarity, and red valour. Myanmar also has a new name: It is now officially known as the Republic of the Union of Myanmar. It was previously known as the Union of Myanmar.   What are the reactions of Myanmar netizens?  dawn_1o9  doesn\u2019t like the new flag    Just received news that our country's flag has changed officially. And I say this here, and I say it loud: I DON'T LIKE THE NEW FLAG!!!   I feel no patriotism when I see this. And the color scheme is the same as Lithuanian flag minus the star, though the hue is different.   I am not the only one who feels like this though. Many are outraged. Personally, I feel like it is an insult.   \u201clooks like a cheap amateurish crap that came out from MS Paint\u201d - my friend's words: not mine.   This is the old flag. Blue stands for peace and stability, red stands for courage and bravery, 14 stars for the 14 states and divisions, the pinion stands for the work force of the country, and the rice stalk stands for the farmers in the country. I love this flag, and it will always be the flag of my country, no matter how much they change it    An interesting conversation in her blog about the topic     awoolham:  Yellow stands for than shwe (author\u2019s note: the leader of Myanmar), green stands for cash, red stands for blood of the people.    ei_angel:  What the!!\u2026They can't change it yet.  Man I hate that flag. Looks like Ethiopian flag or Ghana flag.  So the name has changed to RUM (Republic of the Union of MM) too?  I thought it would only be changed after all the 7 step has taken place.  And that's after the parliament's been called.      dawn_1o9:  @cafengocmy - It looks like a lot of African nation's flags too. With the flag before, Taiwan was the only country whose flag looked like ours. Now, it's about 3 or 4 flags: Ghana, Ethiopia, Lithuania, etc.   The commenter\u2019s reaction about the premature unveiling of the flag was the same sentiment of the opposition. The flag is supposed to be released only after the conduct of the November 7 elections. The opposition accuses the Myanmar military leaders of violating their own constitution.  Min Lwin  of the  Democratic Voice of Burma  adds more information     According to opposition politicians, Burmese law states that the 2008 constitution must come into force before any new flag is raised. This shouldn\u2019t happen until after the controversial 7 November elections.     All the old flags will be burnt. My guess is, the government is so anti-American that even having the same colors, albeit having socialist ideals, isn't going to work.   And in a couple of weeks, we will be voting. Some of us, for the first time in our lives. I voted two years ago at the consulate in Kolkata for the new constitution, in my late 20s, after growing up mostly in democratic countries.   Who will win? The government of course. Now that they're all civilians \u2014 emperors in new clothes, with their new flag. They're going to have the country, too, one way or another. No matter what the people say, do, or think let alone the rest of the world. It doesn't matter what I write here or what you comment, tweet, or who you share this with.    At the comment section of  The Irrawaddy , the conversation continues about the new flag  The new flag is look like exactly the same as the Shan State flag apart from the star instead of white circle inside.  What a shame Than Shwe copied another flag.  Clever move by the junta. It'll look great on T-shirts if tourism ever takes off, and who can really be angry with laid-back rastafarians?  But is the Irrawaddy going to recognise it? Or will \u201cBurma\u201d retain its flag as it fights to stay afloat in the march of history?    Indre : I'm sorry, but why did the government snatch Lithuania's national flag (yellow, green and red) and crossed it so curiously with Vietnam's (star in the center)?    Chindits:  This flag does not represent the country at all. A star?? You know That big white star is also the only star on the colors of Myanmar's tatmadaw, navy, air force and police force. This flag represent only the armed forces.  ",
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
    "story_tags": [
      
    ],
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

 raw_1st_download             0               If non-zero include the full HTML of the first
                                              page of the story
--------------------------------------------------------------------------------------------------------
  
The ‘last_processed_id’ parameter can be used to page through these results. The api will return 20 stories with a processed_id greater than this value.

NOTE: stories_id and processed_id are separate values. The order in which stories are processed is different than the stories_id order. The processing pipeline involves downloading, extracting, and vectoring stories. Since unprocessed stories are of little interest, we have introduced the processed_id field to allow users to stream all stories as they’re processed.

####Example

URL: http://mediacloud.org/api/v2/stories/list_processed/&last_processed_stories_id=86259158&rows=1

```json
[
  {
    "processed_stories_id": "86259159",
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


## Story subsets

These who want to only see a subset of stories can create a story subset stream by sending a put request to `api/v2/stories/subset/?data=\<JSON\> `where \<JSON_STRING\> is a URL encoded JSON representation of the story subset.

###api/v2/stories/subset (PUT)

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

*_Note:_* At least one of the above parameters must by provided.

The put request will return the meta-data representation of the `story_subset` including its database ID.
  
It will take the backend system a while to generate the stream of stories for the newly created subset. There is a background daemon script (`mediawords_process_story_subsets.pl`) that detects newly created subsets and adds stories to them.

####Example

Create a story subset for the New York Times from January 1, 2014 to January 2, 2014

```
curl -X PUT -d media_id=1 -d start_date=2014-01-01 -d end_date=2014-01-02 http://mediacloud.org/api/v2/stories/subset
```

###api/v2/stories/subset (GET)

URL                                                                       Function
---------------------------------      --------------------------------------------------
api/v2/stories/subset                    show the status of a subset. Must use a GET request
---------------------------------      --------------------------------------------------

  
To see the status of a given subset, the client sends a get request to `api/v2/stories/subset/<ID>` where `<ID>` is the database id that was returned in the put request above.  The returned object contains a `'ready'` field with a Boolean value indicating that stories from the subset have been compiled.

####Example 
curl -X GET http://0:3000/api/v2/stories/subset/1
```json
{
   "media_id":1,
   "end_date":"2013-01-02 00:00:00-05",
   "media_sets_id":null,
   "start_date":"2013-01-01 00:00:00-05",
   "last_processed_stories_id":"116335917",
   "ready":1,
   "story_subsets_id":"1"
}
```
 
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

 raw_1st_download             0               If non-zero include the full HTML of the first
                                              page of the story
--------------------------------------------------------------------------------------------------------
 
  
This behaves similarly to the `list_processed` URL above except only stories from the given subset are returned.

##Solr

###api/v2/solr/sentences

####Query Parameters

--------------------------------------------------------------------------------------------------------
Parameter                     Default         Notes
---------------------------   ----------      ----------------------------------------------------------
 q                            N/A               q ( query ) parameter which is passed directly to Solr

 fq                           null              fq (filter query) parameter which is passed directly to Solr

 start                        0                 passed directly to Solr

 rows                         1000              passed directly to Solr

--------------------------------------------------------------------------------------------------------

####Example

Fetch 10 sentences containing the word 'obama' from the New York Times

URL:  http://mediacloud.org/api/v2/solr/sentences?q=sentence%3Aobama&rows=10&fq=media_id%3A1

*TODO* waiting for Solr import to complete to include output

###api/v2/solr/wc

####Query Parameters

--------------------------------------------------------------------------------------------------------
Parameter                     Default         Notes
---------------------------   ----------      ----------------------------------------------------------
 q                            N/A               q ( query ) parameter which is passed directly to Solr

 fq                           null              fq (filter query) parameter which is passed directly to Solr

--------------------------------------------------------------------------------------------------------

Returns word frequency counts for all sentences returned by querying solr using the q and fq parameters.

####Example

Obtain word frequency counts for all sentences containing the word 'obama' in the New York Times

URL:  http://mediacloud.org/api/v2/solr/wc?q=sentence%3Aobama&fq=media_id%3A1

*TODO* waiting for Solr import to complete to include output


##Write Back API

This call allow users to push data into the postgresql database.

###api/v2/stories/custom_tags

URL                                                                       Function
---------------------------------      --------------------------------------------------
api/v2/stories/custom_tags                    Add custom tags to a story. Must be a PUT request
---------------------------------      --------------------------------------------------

####Query Parameters 

--------------------------------------------------------------------------------------------------------
Parameter                     Notes
---------------------------   --------------------------------------------------------------------------
 stories_id                   The id of the story to which to add the custom tags

 custom_tag                   Can be specified multiple times to add multiple tags to the story
--------------------------------------------------------------------------------------------------------

####Example

Set the custom tags on the story with stories_id 1000 to 'foo' and 'bar'

curl -X PUT -d stories_id=10000 -d custom_tag=foo -d custom_tag=bar http://mediacloud.org/api/v2/stories/custom_tags

#Extended Examples

## Output Format / JSON
  
The format of the API responses is determine by the ‘Accept’ header on the request. The default is ‘application/json’. Other supported formats include 'text/html', 'text/x-json', and  'text/x-php-serialization'. It’s recommended that you explicitly set the ‘Accept’ header rather than relying on the default.
 
Here’s an example of setting the ‘Accept’ header in Python

```python  
import pkg_resources  

import requests   
assert pkg_resources.get_distribution("requests").version >= '1.2.3'
 
r = requests.get( 'http://amanda.law.harvard.edu/admin/api/stories/all_processed?page=1', auth=('mediacloud-admin', KEY), headers = { 'Accept': 'application/json'})  

data = r.json()
```

##Create a CSV file with all media sources.

```python
media = []
start = 0
rows  = 100
while True:
      params = { 'start': start, 'rows': rows }
      print "start:{} rows:{}".format( start, rows)
      r = requests.get( 'http://mediacloud.org/api/v2/media/list', params = params, headers = { 'Accept': 'application/json'} )
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

##Grab all processed stories from US Top 25 MSM as a stream

This is broken down into multiple steps for convenience and because that's probably how a real user would do it. 

###Find the media set

We assume that the user is new to Media Cloud. They're interested in what sources we have available. They run curl to get a quick list of the available dashboards.

```
curl http://mediacloud.org/api/v2/dashboards/list&nested_data=0
```

```json
[
 {"dashboards_id":1,"name":"US / English"}
 {"dashboards_id":2,"name":"Russia"}
 {"dashboards_id":3,"name":"test"}
 {"dashboards_id":5,"name":"Russia Full Morningside 2010"}
 {"dashboards_id":4,"name":"Russia Sampled Morningside 2010"}
 {"dashboards_id":6,"name":"US Miscellaneous"}
 {"dashboards_id":7,"name":"Nigeria"}
 {"dashboards_id":101,"name":"techblogs"}
 {"dashboards_id":116,"name":"US 2012 Election"}
 {"dashboards_id":247,"name":"Russian Public Sphere"}
 {"dashboards_id":463,"name":"lithanian"}
 {"dashboards_id":481,"name":"Korean"}
 {"dashboards_id":493,"name":"California"}
 {"dashboards_id":773,"name":"Egypt"}
]
```

The user sees the "US / English" dashboard with dashboards_id 1 and asks for more detailed information.

```
curl http://mediacloud.org/api/v2/dashboards/single/1
```

```json
[
   {
      "name":"US / English",
      "dashboards_id": "1",
      "media_sets":
      [
         {
      	 "media_sets_id":1,
	 "name":"Top 25 Mainstream Media",
	 "description":"Top 25 mainstream media sources by monthly unique users from the U.S. according to the Google AdPlanner service.",
	 media:
	   [
	     NOT SHOWN FOR SPACE REASONS 
	   ]
	 },
   	 {
	 "media_sets_id":26,
	 "name":"Popular Blogs",
	 "description":"1000 most popular feeds in bloglines.",
	  media:
	   [
	     NOT SHOWN FOR SPACE REASONS 
	   ]
   	   }
   ]  
]
```

*Note* the list of media are not shown for space reasons.

After looking at this output, the user decides that she is interested in the "Top 25 Mainstream Media" set with media_id 1.

###Create a subset

curl -X PUT -d media_set_id=1 http://mediacloud.org/api/v2/stories/subset

Save the story_subsets_id

###Wait until the subset is ready

Below we show some python code to continuously determine whether the subset has been processed. Users could do something similar manually by issuing curl requests.

```python
import requests 
import time

while True:
    r = requests.get( 'http://mediacloud.org/api/v2/stories/subset/' + story_subsets_id, headers = { 'Accept': 'application/json'} )
    data = r.json()

    if data['ready'] == '1':
       break
    else:
       time.sleep 120

print "subset {} is ready".format( story_subsets_id )
```

###Grab stories from the processed stream

Since the subset is now processed we can obtain all of its stories by repeatedly list_subset_processed and changing the last_processed_stories_id parameter. This is shown in 
the python code below where process_stories is a user provided function to process this data.

```python
import requests

start = 0
rows  = 100
while True:
      params = { 'last_processed_stories_id': start, 'rows': rows }

      print "Fetching {} stories starting from {}".format( rows, start)
      r = requests.get( 'http://mediacloud.org/api/v2/stories/list_subset_processed/' +  story_subsets_id, params = params, headers = { 'Accept': 'application/json'} )
      stories = r.json()

      if len(stories) == 0:
      	 break

      start += rows

      process_stories( stories )
```


##Get word counts for top words for sentences matching 'trayvon' in U.S. Political Blogs during April 2012

This is broken down into multiple steps for convenience and because that's probably how a real user would do it. 

###Find the media set

We assume that the user is new to Media Cloud. They're interested in what sources we have available. They run curl to get a quick list of the available dashboards.

```
curl http://mediacloud.org/api/v2/dashboards/list&nested_data=0
```

```json
[
 {"dashboards_id":1,"name":"US / English"}
 {"dashboards_id":2,"name":"Russia"}
 {"dashboards_id":3,"name":"test"}
 {"dashboards_id":5,"name":"Russia Full Morningside 2010"}
 {"dashboards_id":4,"name":"Russia Sampled Morningside 2010"}
 {"dashboards_id":6,"name":"US Miscellaneous"}
 {"dashboards_id":7,"name":"Nigeria"}
 {"dashboards_id":101,"name":"techblogs"}
 {"dashboards_id":116,"name":"US 2012 Election"}
 {"dashboards_id":247,"name":"Russian Public Sphere"}
 {"dashboards_id":463,"name":"lithanian"}
 {"dashboards_id":481,"name":"Korean"}
 {"dashboards_id":493,"name":"California"}
 {"dashboards_id":773,"name":"Egypt"}
]
```

The user sees the "US / English" dashboard with dashboards_id 1 and asks for more detailed information.

```
curl http://mediacloud.org/api/v2/dashboards/single/1
```

```json
[
   {
      "name":"dashboard 2",
      "dashboards_id": "2",
      "media_sets":
      [
         {
      	 "media_sets_id":1,
	 "name":"Top 25 Mainstream Media",
	 "description":"Top 25 mainstream media sources by monthly unique users from the U.S. according to the Google AdPlanner service.",
	 media:
	   [
	     NOT SHOWN FOR SPACE REASONS 
	   ]
	 },
   	 {
	 "media_sets_id":26,
	 "name":"Popular Blogs",
	 "description":"1000 most popular feeds in bloglines.",
	  "media":
	   [
	     NOT SHOWN FOR SPACE REASONS 
	   ]
   	 },
	 {
	     "media_sets_id": 7125,
             "name": "Political Blogs",
	     "description": "1000 most influential U.S. political blogs according to Technorati, pruned of mainstream media sources.",
	     "media":
	   [
	     NOT SHOWN FOR SPACE REASONS 
	   ]

	  }
   ]  
]
```

*Note* the list of media are not shown for space reasons.

After looking at this output, the user decides that she is interested in the "Political Blogs" set with media_id 7125.

###Make a request for the word counts based on media_sets_id and sentence text and date range

One way to appropriately restrict the data is by setting the q parameter to restrict by sentence content and then the fq parameter twice to restrict by media_sets_id and publish_date.
Below q is set to "sentence:trayvon" and fq is set to "media_sets_id:7135" and  "publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]". (Note that ":", "[", and "]" are URL encoded.)

curl 'http://mediacloud.org/api/v2/solr/wc?q=sentence%3Atrayvon&fq=media_sets_id%3A7125&fq=publish_date%3A%5B2012-04-01T00%3A00%3A00.000Z+TO+2013-05-01T00%3A00%3A00.000Z%5D'

Alternatively, we could use a single large query by setting q to "sentence:trayvon AND media_sets_id:7135 AND publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]". 

curl 'http://mediacloud.org/api/v2/solr/wc?q=sentence%3Atrayvon+AND+media_sets_id%3A7135+AND+publish_date%3A%5B2012-04-01T00%3A00%3A00.000Z+TO+2013-05-01T00%3A00%3A00.000Z%5D&fq=media_sets_id%3A7135&fq=publish_date%3A%5B2012-04-01T00%3A00%3A00.000Z+TO+2013-05-01T00%3A00%3A00.000Z%5D'

*TODO* show output

##Grab all stories in the New York Times during October 2012


###Find the media_id of the New York Times -- TODO

###Create a subset
curl -X PUT -d start_date=2012-10-01 -d end_date=2012-11-01 -d media_id=1 http://mediacloud.org/api/v2/stories/subset

Save the story_subsets_id

###Wait until the subset is ready

See the 25 main stream media example above.

###Grab stories from the processed stream

See the 25 main stream media example above.

