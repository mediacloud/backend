% Media Cloud API Version 2
% Author David Larochelle

<!--- This file is intended to be parsed by the pandoc markdown engine.
      It is not guaranteed to display correctly with other markdown engines.
--->

#API URLs

*Note* by default the API only returns a subset of the available fields in returned objects. The returned fields are those that we consider to be the most relevant to
users of the API. If the all_fields parameter is provided and is non-zero, then a most complete list of fields will be returned.

## Media

### api/v2/media/single/

URL                                    Function
---------------------------------      ------------------------------------------------------------
api/v2/media/single/\<media_id\>         Return the media source in which media_id equals \<media_id\>
---------------------------------      ------------------------------------------------------------

####Query Parameters 

None.

####Example

Fetching information on the New York Times

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
 last_media_id    0               Return media sources with a 
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

URL                                          Function
---------------------------------            ------------------------------------------------------------
api/v2/media_set/single/\<media_sets_id\>         Return the media set in which media_sets_id equals \<media_sets_id\>
---------------------------------            ------------------------------------------------------------

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
 last_media_sets_id    0               Return media sets with 
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

## Feeds

###api/v2/feeds/single

URL                                      Function
---------------------------------        ------------------------------------------------------------
api/v2/feeds/single/\<feeds_id\>         Return the feeds in which feeds_id equals \<feeds_id\>
---------------------------------        ------------------------------------------------------------

####Query Parameters 

None.

####Example

URL: http://mediacloud.org/api/v2/feeds/single/1

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
 last_feeds_id         0               Return feeda with 
                                       feeds_id is greater than this value

 rows                  20              Number of feeds to return. Cannot be larger than 100
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
 last_dashboards_id    0               Return dashboards in which 
                                       dashboards_id greater than this value

 rows                  20              Number of dashboards to return. Can not be larger than 100

 nested_data             1             If 0 return only the name and dashboards_id; otherwise 
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


###Output description

The following table describes the meaning and origin of fields returned by both api/v2/stories/single and api/v2/stories/list_processed

--------------------------------------------------------------------------------------------------------
Field                    Description
-------------------      ----------------------------------------------------------------------
 title                    The story title as defined in the RSS feed. (May or may not contain
                           HTML depending on the source)

 description              The story description as defined in the RSS feed. (May or may not contain
                           HTML depending on the source)

 full_text_rss            1 if the text of the story was obtained through the RSS feed. 
                          0 if the text of the story was optained by extracting the article text from the HTML

 story_text               The text of the story. If full_text_rss is non-zero, this is formed by HTML stripping the title, HTML 
                          stripping the description, and concatenating them.
                          If full_text_rss is non-zero, this is formed by extracting the article text from the HTML.

 story_sentences          A list of sentences in the story. Generated from story_text by splitting it into sentences
                          and removing any duplicate sentences oocuring within the same source for the same week

 raw_1st_download         The contents of the first HTML page of the story. 
                          Available regards of the value of full_text_rss.
                          NOTE: only provided if the raw_1st_download parameter is non-zero.

 publish_date             The publish date of the story as specified in the RSS feed

 custom_story_tags        A list containing the names of any tags that have been added to the
                          story using the write-back API.

 collect_date             The date the RSS feed was actually downloaded

 guid                     The GUID field in the RSS feed default to the URL if no GUID is specified?
 
--------------------------------------------------------------------------------------------------------


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

Note: This fetches data on the CC licensed Global Voices Story ["Myanmar's new flag and new name"](http://globalvoicesonline.org/2010/10/26/myanmars-new-flag-and-new-name/#comment-1733161) from November 2010.

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
    "custom_story_tags": [
       "custom_tag_1",
       "custom_tag_2"
    ],
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
 last_processed_stories_id    0               Return stories in which the processed_stories_id 
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

Users who want to only see a subset of stories can create a story subset stream by sending a put request to `api/v2/stories/subset/`.

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

 custom_story_tag             only include stories in which custom_story_tag in one of the custom_story_tags

--------------------------------------------------------------------------------------------------------

*_Note:_* At least one of the above parameters must by provided.

The put request will return the meta-data representation of the `story_subset` including its database ID.
  
It will take the backend system a while to generate the stream of stories for the newly created subset. There is a background daemon script (`mediawords_process_story_subsets.pl`) that detects newly created subsets and adds stories to them.

####Example

Create a story subset for the New York Times from January 1, 2014 to January 2, 2014

```
curl -X PUT -d media_id=1 -d start_date=2014-01-01 -d end_date=2014-01-02 http://mediacloud.org/api/v2/stories/subset
```

```json
{
   "media_id":1,
   "end_date":"2014-01-02 00:00:00-00",
   "media_sets_id":null,
   "start_date":"2014-01-01 00:00:00-00",
   "ready":0,
   "story_subsets_id":"1"
}
```

###api/v2/stories/subset (GET)

URL                                                                       Function
---------------------------------      --------------------------------------------------
api/v2/stories/subset                    show the status of a subset. Must use a GET request
---------------------------------      --------------------------------------------------

  
To see the status of a given subset, the client sends a get request to `api/v2/stories/subset/<ID>` where `<ID>` is the database id that was returned in the put request above. **The returned object contains a `ready` field with a Boolean value indicating that stories from the subset have been compiled.**

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

URL                                           Function
--------------------------------------------  ------------------------------------------------

api/V2/stories/list_subset_processed/\<id\>      Return multiple processed stories
                                                 from a subset. \<id\> is the id of the subset

--------------------------------------------  ------------------------------------------------

####Query Parameters

--------------------------------------------------------------------------------------------------------
Parameter                     Default         Notes
---------------------------   ----------      ----------------------------------------------------------
 last_processed_stories_id    0               Return stories in which the processed_stories_id 
                                                is greater than this value

 rows                         20              Number of stories to return. Cannot be larger than 100

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

See the [Solr documentation](http://wiki.apache.org/solr/CommonQueryParameters) for a detailed description of these 4 parameters.

####Example

Fetch 10 sentences containing the word 'obama' from the New York Times

URL:  http://mediacloud.org/api/v2/solr/sentences?q=sentence%3Aobama&rows=10&fq=media_id%3A1

```json
[
  {
    "id": "959545252_ss",
    "field_type": "ss",
    "publish_date": "2012-04-18T16:10:06Z",
    "media_id": 1,
    "story_sentences_id": "959545252",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama:",
    "sentence_number": 16,
    "stories_id": 79115414,
    "custom_story_tags": [
      "custom_tag_1",
      "custom_tag_2"
    ],
    "custom_sentence_tags": [
      "custom_tag_A",
      "custom_tag_B"
    ],
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "tags_id_stories": [
      8878051,
      8878085
    ],
    "_version_": 1.4579959345877e+18
  },
  {
    "id": "816034983_ss",
    "field_type": "ss",
    "publish_date": "2011-10-04T09:15:23Z",
    "media_id": 1,
    "story_sentences_id": "816034983",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama!",
    "sentence_number": 8,
    "stories_id": 42553267,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4580934893476e+18
  },
  {
    "id": "989267715_ss",
    "field_type": "ss",
    "publish_date": "2012-07-27T18:28:39Z",
    "media_id": 1,
    "story_sentences_id": "989267715",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama.",
    "sentence_number": 37,
    "stories_id": 84392662,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4581006291981e+18
  },
  {
    "id": "984233265_ss",
    "field_type": "ss",
    "publish_date": "2012-06-25T08:55:01Z",
    "media_id": 1,
    "story_sentences_id": "984233265",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "\u201cObama!",
    "sentence_number": 11,
    "stories_id": 83655229,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4580994786753e+18
  },
  {
    "id": "1385764992_ss",
    "field_type": "ss",
    "publish_date": "2013-05-20T18:18:05Z",
    "media_id": 1,
    "story_sentences_id": "1385764992",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama:",
    "sentence_number": 20,
    "stories_id": 118733470,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4581887058062e+18
  },
  {
    "id": "2085684494_ss",
    "field_type": "ss",
    "publish_date": "2012-09-01T06:01:17Z",
    "media_id": 1,
    "story_sentences_id": "2085684494",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama!\u201d",
    "sentence_number": 40,
    "language": "en",
    "stories_id": 169890506,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "tags_id_stories": [
      8875452,
      8877812
    ],
    "_version_": 1.4583751421544e+18
  },
  {
    "id": "947364128_ss",
    "field_type": "ss",
    "publish_date": "2012-05-02T13:00:35Z",
    "media_id": 1,
    "story_sentences_id": "947364128",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama agreed.",
    "sentence_number": 169,
    "stories_id": 80058349,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4579989989955e+18
  },
  {
    "id": "916030816_ss",
    "field_type": "ss",
    "publish_date": "2012-04-04T00:08:33Z",
    "media_id": 1,
    "story_sentences_id": "916030816",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama Foodorama",
    "sentence_number": 138,
    "stories_id": 77777319,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4580065399325e+18
  },
  {
    "id": "915146557_ss",
    "field_type": "ss",
    "publish_date": "2010-11-03T04:18:40Z",
    "media_id": 1,
    "story_sentences_id": "915146557",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "OBAMA 3",
    "sentence_number": 12,
    "stories_id": 76521646,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4580067639912e+18
  },
  {
    "id": "911745123_ss",
    "field_type": "ss",
    "publish_date": "2012-01-03T11:13:06Z",
    "media_id": 1,
    "story_sentences_id": "911745123",
    "solr_import_date": "2014-01-23T04:28:14.894Z",
    "sentence": "Obama bad.",
    "sentence_number": 46,
    "stories_id": 46771580,
    "media_sets_id": [
      24,
      1,
      16959
    ],
    "tags_id_media": [
      8874930,
      1,
      109,
      6729599,
      6071565,
      8875027
    ],
    "_version_": 1.4580076258599e+18
  }
]
```

###api/v2/solr/wc

####Query Parameters

--------------------------------------------------------------------------------------------------------
Parameter                     Default         Notes
---------------------------   ----------      ----------------------------------------------------------
 q                            N/A               q ( query ) parameter which is passed directly to Solr

 fq                           null              fq (filter query) parameter which is passed directly to Solr

--------------------------------------------------------------------------------------------------------

Returns word frequency counts for all sentences returned by querying solr using the q and fq parameters.

See the [Solr documentation](http://wiki.apache.org/solr/CommonQueryParameters) for a detailed description of q and fq.

####Example

Obtain word frequency counts for all sentences containing the word 'obama' in the New York Times

URL:  http://mediacloud.org/api/v2/solr/wc?q=sentence%3Aobama&fq=media_id%3A1

```json
[
  {
    "count": 91778,
    "stem": "obama",
    "term": "obama"
  },
  {
    "count": 10455,
    "stem": "republican",
    "term": "republicans"
  },
  {
    "count": 7969,
    "stem": "romnei",
    "term": "romney"
  },
  {
    "count": 6586,
    "stem": "campaign",
    "term": "campaign"
  },
  {
    "count": 6351,
    "stem": "american",
    "term": "american"
  },
  {
    "count": 5825,
    "stem": "democrat",
    "term": "democrats"
  },
  {
    "count": 4844,
    "stem": "washington",
    "term": "washington"
  },
  {
    "count": 4435,
    "stem": "congress",
    "term": "congress"
  },
  {
    "count": 4146,
    "stem": "barack",
    "term": "barack"
  },
  {
    "count": 3983,
    "stem": "tax",
    "term": "tax"
  },
  {
    "count": 2533,
    "stem": "clinton",
    "term": "clinton"
  },
  {
    "count": 2377,
    "stem": "econom",
    "term": "economic"
  },
  {
    "count": 2213,
    "stem": "poll",
    "term": "polls"
  },
  {
    "count": 2212,
    "stem": "mitt",
    "term": "mitt"
  },
  {
    "count": 2168,
    "stem": "economi",
    "term": "economy"
  },
  {
    "count": 2074,
    "stem": "presidenti",
    "term": "presidential"
  },
  {
    "count": 1964,
    "stem": "debt",
    "term": "debt"
  },
  {
    "count": 1953,
    "stem": "bush",
    "term": "bush"
  },
  {
    "count": 1720,
    "stem": "america",
    "term": "america"
  },
  {
    "count": 1700,
    "stem": "war",
    "term": "war"
  },
  {
    "count": 1574,
    "stem": "john",
    "term": "john"
  },
  {
    "count": 1541,
    "stem": "iran",
    "term": "iran"
  },
  {
    "count": 1458,
    "stem": "immigr",
    "term": "immigration"
  },
  {
    "count": 1350,
    "stem": "conserv",
    "term": "conservative"
  },
  {
    "count": 1324,
    "stem": "israel",
    "term": "israel"
  },
  {
    "count": 1292,
    "stem": "afghanistan",
    "term": "afghanistan"
  },
  {
    "count": 1269,
    "stem": "china",
    "term": "china"
  },
  {
    "count": 1252,
    "stem": "michel",
    "term": "michelle"
  },
  {
    "count": 1237,
    "stem": "deficit",
    "term": "deficit"
  },
  {
    "count": 1219,
    "stem": "boehner",
    "term": "boehner"
  },
  {
    "count": 1173,
    "stem": "nuclear",
    "term": "nuclear"
  },
  {
    "count": 1080,
    "stem": "nomin",
    "term": "nomination"
  },
  {
    "count": 967,
    "stem": "famili",
    "term": "family"
  },
  {
    "count": 919,
    "stem": "libya",
    "term": "libya"
  },
  {
    "count": 871,
    "stem": "syria",
    "term": "syria"
  },
  {
    "count": 870,
    "stem": "ohio",
    "term": "ohio"
  },
  {
    "count": 845,
    "stem": "weapon",
    "term": "weapons"
  },
  {
    "count": 844,
    "stem": "crisi",
    "term": "crisis"
  },
  {
    "count": 809,
    "stem": "fact",
    "term": "fact"
  },
  {
    "count": 803,
    "stem": "medicar",
    "term": "medicare"
  },
  {
    "count": 780,
    "stem": "mccain",
    "term": "mccain"
  },
  {
    "count": 779,
    "stem": "david",
    "term": "david"
  },
  {
    "count": 771,
    "stem": "bin",
    "term": "bin"
  },
  {
    "count": 769,
    "stem": "laden",
    "term": "laden"
  },
  {
    "count": 763,
    "stem": "colleg",
    "term": "college"
  },
  {
    "count": 758,
    "stem": "georg",
    "term": "george"
  },
  {
    "count": 749,
    "stem": "minist",
    "term": "minister"
  },
  {
    "count": 747,
    "stem": "educ",
    "term": "education"
  },
  {
    "count": 744,
    "stem": "agreem",
    "term": "agreement"
  },
  {
    "count": 742,
    "stem": "lawmak",
    "term": "lawmakers"
  },
  {
    "count": 733,
    "stem": "caucu",
    "term": "caucus"
  },
  {
    "count": 716,
    "stem": "agenda",
    "term": "agenda"
  },
  {
    "count": 716,
    "stem": "victori",
    "term": "victory"
  },
  {
    "count": 716,
    "stem": "netanyahu",
    "term": "netanyahu"
  },
  {
    "count": 713,
    "stem": "iraq",
    "term": "iraq"
  },
  {
    "count": 702,
    "stem": "ryan",
    "term": "ryan"
  },
  {
    "count": 691,
    "stem": "pakistan",
    "term": "pakistan"
  },
  {
    "count": 681,
    "stem": "student",
    "term": "students"
  },
  {
    "count": 676,
    "stem": "nomine",
    "term": "nominee"
  },
  {
    "count": 662,
    "stem": "hillari",
    "term": "hillary"
  },
  {
    "count": 659,
    "stem": "biden",
    "term": "biden"
  },
  {
    "count": 656,
    "stem": "climat",
    "term": "climate"
  },
  {
    "count": 622,
    "stem": "isra",
    "term": "israeli"
  },
  {
    "count": 609,
    "stem": "arm",
    "term": "arms"
  },
  {
    "count": 604,
    "stem": "chicago",
    "term": "chicago"
  },
  {
    "count": 598,
    "stem": "overhaul",
    "term": "overhaul"
  },
  {
    "count": 593,
    "stem": "prais",
    "term": "praised"
  },
  {
    "count": 592,
    "stem": "florida",
    "term": "florida"
  },
  {
    "count": 589,
    "stem": "independ",
    "term": "independent"
  },
  {
    "count": 587,
    "stem": "iowa",
    "term": "iowa"
  },
  {
    "count": 583,
    "stem": "egypt",
    "term": "egypt"
  },
  {
    "count": 580,
    "stem": "intellig",
    "term": "intelligence"
  },
  {
    "count": 577,
    "stem": "ralli",
    "term": "rally"
  },
  {
    "count": 572,
    "stem": "virginia",
    "term": "virginia"
  },
  {
    "count": 570,
    "stem": "russia",
    "term": "russia"
  },
  {
    "count": 569,
    "stem": "endors",
    "term": "endorsed"
  },
  {
    "count": 555,
    "stem": "stimulu",
    "term": "stimulus"
  },
  {
    "count": 553,
    "stem": "palestinian",
    "term": "palestinian"
  },
  {
    "count": 552,
    "stem": "acknowledg",
    "term": "acknowledged"
  },
  {
    "count": 551,
    "stem": "pre",
    "term": "pres"
  },
  {
    "count": 549,
    "stem": "media",
    "term": "media"
  },
  {
    "count": 544,
    "stem": "pledg",
    "term": "pledged"
  },
  {
    "count": 543,
    "stem": "elector",
    "term": "electoral"
  },
  {
    "count": 527,
    "stem": "global",
    "term": "global"
  },
  {
    "count": 524,
    "stem": "gingrich",
    "term": "gingrich"
  },
  {
    "count": 520,
    "stem": "paul",
    "term": "paul"
  },
  {
    "count": 508,
    "stem": "trillion",
    "term": "trillion"
  },
  {
    "count": 506,
    "stem": "commiss",
    "term": "commission"
  },
  {
    "count": 506,
    "stem": "oppon",
    "term": "opponent"
  },
  {
    "count": 503,
    "stem": "raiser",
    "term": "raiser"
  },
  {
    "count": 502,
    "stem": "bipartisan",
    "term": "bipartisan"
  },
  {
    "count": 497,
    "stem": "korea",
    "term": "korea"
  },
  {
    "count": 493,
    "stem": "children",
    "term": "children"
  },
  {
    "count": 488,
    "stem": "drone",
    "term": "drone"
  },
  {
    "count": 487,
    "stem": "free",
    "term": "free"
  },
  {
    "count": 486,
    "stem": "prioriti",
    "term": "priorities"
  },
  {
    "count": 471,
    "stem": "anti",
    "term": "anti"
  },
  {
    "count": 462,
    "stem": "corpor",
    "term": "corporate"
  },
  {
    "count": 460,
    "stem": "assert",
    "term": "assertion"
  },
  {
    "count": 459,
    "stem": "donor",
    "term": "donors"
  },
  {
    "count": 456,
    "stem": "rival",
    "term": "rivals"
  },
  {
    "count": 450,
    "stem": "advoc",
    "term": "advocates"
  },
  {
    "count": 448,
    "stem": "illeg",
    "term": "illegal"
  },
  {
    "count": 445,
    "stem": "carolina",
    "term": "carolina"
  },
  {
    "count": 441,
    "stem": "suprem",
    "term": "supreme"
  },
  {
    "count": 441,
    "stem": "unemploy",
    "term": "unemployment"
  },
  {
    "count": 440,
    "stem": "qaeda",
    "term": "qaeda"
  },
  {
    "count": 439,
    "stem": "summit",
    "term": "summit"
  },
  {
    "count": 439,
    "stem": "labor",
    "term": "labor"
  },
  {
    "count": 438,
    "stem": "terror",
    "term": "terrorism"
  },
  {
    "count": 433,
    "stem": "terrorist",
    "term": "terrorist"
  },
  {
    "count": 430,
    "stem": "kerri",
    "term": "kerry"
  },
  {
    "count": 430,
    "stem": "super",
    "term": "super"
  },
  {
    "count": 429,
    "stem": "european",
    "term": "european"
  },
  {
    "count": 426,
    "stem": "embrac",
    "term": "embraced"
  },
  {
    "count": 425,
    "stem": "california",
    "term": "california"
  },
  {
    "count": 423,
    "stem": "perri",
    "term": "perry"
  },
  {
    "count": 421,
    "stem": "environment",
    "term": "environmental"
  },
  {
    "count": 420,
    "stem": "recess",
    "term": "recession"
  },
  {
    "count": 420,
    "stem": "aggress",
    "term": "aggressive"
  },
  {
    "count": 419,
    "stem": "inaugur",
    "term": "inauguration"
  },
  {
    "count": 416,
    "stem": "sanction",
    "term": "sanctions"
  },
  {
    "count": 416,
    "stem": "rodham",
    "term": "rodham"
  },
  {
    "count": 406,
    "stem": "robert",
    "term": "robert"
  },
  {
    "count": 405,
    "stem": "withdraw",
    "term": "withdrawal"
  },
  {
    "count": 402,
    "stem": "gov",
    "term": "gov"
  },
  {
    "count": 400,
    "stem": "deport",
    "term": "deportation"
  },
  {
    "count": 399,
    "stem": "chines",
    "term": "chinese"
  },
  {
    "count": 392,
    "stem": "qaddafi",
    "term": "qaddafi"
  },
  {
    "count": 392,
    "stem": "osama",
    "term": "osama"
  },
  {
    "count": 390,
    "stem": "santorum",
    "term": "santorum"
  },
  {
    "count": 390,
    "stem": "option",
    "term": "options"
  },
  {
    "count": 388,
    "stem": "pentagon",
    "term": "pentagon"
  },
  {
    "count": 388,
    "stem": "headlin",
    "term": "headline"
  },
  {
    "count": 387,
    "stem": "assad",
    "term": "assad"
  },
  {
    "count": 380,
    "stem": "ban",
    "term": "ban"
  },
  {
    "count": 378,
    "stem": "fuel",
    "term": "fuel"
  },
  {
    "count": 378,
    "stem": "wisconsin",
    "term": "wisconsin"
  },
  {
    "count": 377,
    "stem": "tea",
    "term": "tea"
  },
  {
    "count": 377,
    "stem": "violenc",
    "term": "violence"
  },
  {
    "count": 377,
    "stem": "fox",
    "term": "fox"
  },
  {
    "count": 376,
    "stem": "vow",
    "term": "vowed"
  },
  {
    "count": 375,
    "stem": "massachusett",
    "term": "massachusetts"
  },
  {
    "count": 374,
    "stem": "twitter",
    "term": "twitter"
  },
  {
    "count": 371,
    "stem": "syrian",
    "term": "syrian"
  },
  {
    "count": 367,
    "stem": "arizona",
    "term": "arizona"
  },
  {
    "count": 366,
    "stem": "wealthi",
    "term": "wealthy"
  },
  {
    "count": 366,
    "stem": "nato",
    "term": "nato"
  },
  {
    "count": 363,
    "stem": "spokesman",
    "term": "spokesman"
  },
  {
    "count": 358,
    "stem": "asia",
    "term": "asia"
  },
  {
    "count": 355,
    "stem": "arab",
    "term": "arab"
  },
  {
    "count": 352,
    "stem": "europ",
    "term": "europe"
  },
  {
    "count": 350,
    "stem": "valu",
    "term": "values"
  },
  {
    "count": 348,
    "stem": "pac",
    "term": "pac"
  },
  {
    "count": 347,
    "stem": "mexico",
    "term": "mexico"
  },
  {
    "count": 346,
    "stem": "texa",
    "term": "texas"
  },
  {
    "count": 346,
    "stem": "renew",
    "term": "renewed"
  },
  {
    "count": 344,
    "stem": "repeal",
    "term": "repeal"
  },
  {
    "count": 342,
    "stem": "mandat",
    "term": "mandate"
  },
  {
    "count": 334,
    "stem": "facebook",
    "term": "facebook"
  },
  {
    "count": 330,
    "stem": "mcconnel",
    "term": "mcconnell"
  },
  {
    "count": 329,
    "stem": "treasuri",
    "term": "treasury"
  },
  {
    "count": 328,
    "stem": "muslim",
    "term": "muslim"
  },
  {
    "count": 326,
    "stem": "capitol",
    "term": "capitol"
  },
  {
    "count": 324,
    "stem": "pro",
    "term": "pro"
  },
  {
    "count": 322,
    "stem": "disappoint",
    "term": "disappointed"
  },
  {
    "count": 320,
    "stem": "african",
    "term": "african"
  },
  {
    "count": 320,
    "stem": "afghan",
    "term": "afghan"
  },
  {
    "count": 314,
    "stem": "trail",
    "term": "trail"
  },
  {
    "count": 314,
    "stem": "iranian",
    "term": "iranian"
  },
  {
    "count": 313,
    "stem": "predict",
    "term": "predicted"
  },
  {
    "count": 312,
    "stem": "pipelin",
    "term": "pipeline"
  },
  {
    "count": 308,
    "stem": "joseph",
    "term": "joseph"
  },
  {
    "count": 308,
    "stem": "mayor",
    "term": "mayor"
  },
  {
    "count": 307,
    "stem": "veto",
    "term": "veto"
  },
  {
    "count": 307,
    "stem": "latino",
    "term": "latino"
  },
  {
    "count": 305,
    "stem": "ambassador",
    "term": "ambassador"
  },
  {
    "count": 304,
    "stem": "hispan",
    "term": "hispanic"
  },
  {
    "count": 303,
    "stem": "freedom",
    "term": "freedom"
  },
  {
    "count": 303,
    "stem": "reid",
    "term": "reid"
  },
  {
    "count": 302,
    "stem": "treati",
    "term": "treaty"
  },
  {
    "count": 301,
    "stem": "nevada",
    "term": "nevada"
  },
  {
    "count": 300,
    "stem": "space",
    "term": "space"
  },
  {
    "count": 300,
    "stem": "palin",
    "term": "palin"
  },
  {
    "count": 299,
    "stem": "rick",
    "term": "rick"
  },
  {
    "count": 297,
    "stem": "putin",
    "term": "putin"
  },
  {
    "count": 297,
    "stem": "celebr",
    "term": "celebrate"
  },
  {
    "count": 295,
    "stem": "predecessor",
    "term": "predecessor"
  },
  {
    "count": 294,
    "stem": "midterm",
    "term": "midterm"
  },
  {
    "count": 294,
    "stem": "highlight",
    "term": "highlight"
  },
  {
    "count": 292,
    "stem": "michael",
    "term": "michael"
  },
  {
    "count": 292,
    "stem": "sept",
    "term": "sept"
  },
  {
    "count": 291,
    "stem": "scienc",
    "term": "science"
  },
  {
    "count": 290,
    "stem": "frustrat",
    "term": "frustration"
  },
  {
    "count": 285,
    "stem": "russian",
    "term": "russian"
  },
  {
    "count": 282,
    "stem": "activist",
    "term": "activists"
  },
  {
    "count": 281,
    "stem": "mubarak",
    "term": "mubarak"
  },
  {
    "count": 278,
    "stem": "medicaid",
    "term": "medicaid"
  },
  {
    "count": 278,
    "stem": "true",
    "term": "true"
  },
  {
    "count": 277,
    "stem": "studi",
    "term": "study"
  },
  {
    "count": 275,
    "stem": "rebel",
    "term": "rebels"
  },
  {
    "count": 271,
    "stem": "colorado",
    "term": "colorado"
  },
  {
    "count": 269,
    "stem": "solution",
    "term": "solution"
  },
  {
    "count": 269,
    "stem": "guant",
    "term": "guant"
  },
  {
    "count": 268,
    "stem": "namo",
    "term": "namo"
  },
  {
    "count": 267,
    "stem": "ensur",
    "term": "ensure"
  },
  {
    "count": 265,
    "stem": "revers",
    "term": "reverse"
  },
  {
    "count": 264,
    "stem": "opinion",
    "term": "opinion"
  },
  {
    "count": 264,
    "stem": "analyst",
    "term": "analysts"
  },
  {
    "count": 264,
    "stem": "leak",
    "term": "leaks"
  },
  {
    "count": 260,
    "stem": "benjamin",
    "term": "benjamin"
  },
  {
    "count": 258,
    "stem": "cnn",
    "term": "cnn"
  },
  {
    "count": 257,
    "stem": "strategist",
    "term": "strategist"
  },
  {
    "count": 257,
    "stem": "pennsylvania",
    "term": "pennsylvania"
  },
  {
    "count": 257,
    "stem": "professor",
    "term": "professor"
  },
  {
    "count": 256,
    "stem": "detaine",
    "term": "detainees"
  },
  {
    "count": 254,
    "stem": "shutdown",
    "term": "shutdown"
  },
  {
    "count": 253,
    "stem": "internet",
    "term": "internet"
  },
  {
    "count": 252,
    "stem": "raid",
    "term": "raid"
  },
  {
    "count": 250,
    "stem": "broader",
    "term": "broader"
  },
  {
    "count": 250,
    "stem": "expir",
    "term": "expire"
  },
  {
    "count": 249,
    "stem": "surveil",
    "term": "surveillance"
  },
  {
    "count": 248,
    "stem": "love",
    "term": "love"
  },
  {
    "count": 247,
    "stem": "illinoi",
    "term": "illinois"
  },
  {
    "count": 247,
    "stem": "reviv",
    "term": "revive"
  },
  {
    "count": 247,
    "stem": "mortgag",
    "term": "mortgage"
  },
  {
    "count": 247,
    "stem": "oval",
    "term": "oval"
  },
  {
    "count": 246,
    "stem": "deputi",
    "term": "deputy"
  },
  {
    "count": 246,
    "stem": "hampshir",
    "term": "hampshire"
  },
  {
    "count": 245,
    "stem": "bloomberg",
    "term": "bloomberg"
  },
  {
    "count": 243,
    "stem": "yemen",
    "term": "yemen"
  },
  {
    "count": 243,
    "stem": "hawaii",
    "term": "hawaii"
  },
  {
    "count": 242,
    "stem": "echo",
    "term": "echoed"
  },
  {
    "count": 242,
    "stem": "gulf",
    "term": "gulf"
  },
  {
    "count": 241,
    "stem": "libyan",
    "term": "libyan"
  },
  {
    "count": 240,
    "stem": "bargain",
    "term": "bargain"
  },
  {
    "count": 239,
    "stem": "infrastructur",
    "term": "infrastructure"
  },
  {
    "count": 239,
    "stem": "reagan",
    "term": "reagan"
  },
  {
    "count": 239,
    "stem": "coalition",
    "term": "coalition"
  },
  {
    "count": 239,
    "stem": "harri",
    "term": "harry"
  },
  {
    "count": 238,
    "stem": "borrow",
    "term": "borrowing"
  },
  {
    "count": 237,
    "stem": "ceremoni",
    "term": "ceremony"
  },
  {
    "count": 236,
    "stem": "amid",
    "term": "amid"
  },
  {
    "count": 236,
    "stem": "jai",
    "term": "jay"
  },
  {
    "count": 235,
    "stem": "chamber",
    "term": "chamber"
  },
  {
    "count": 235,
    "stem": "economist",
    "term": "economists"
  },
  {
    "count": 233,
    "stem": "africa",
    "term": "africa"
  },
  {
    "count": 231,
    "stem": "photo",
    "term": "photo"
  },
  {
    "count": 231,
    "stem": "assault",
    "term": "assault"
  },
  {
    "count": 231,
    "stem": "cameron",
    "term": "cameron"
  },
  {
    "count": 229,
    "stem": "credibl",
    "term": "credible"
  },
  {
    "count": 229,
    "stem": "karzai",
    "term": "karzai"
  },
  {
    "count": 229,
    "stem": "carnei",
    "term": "carney"
  },
  {
    "count": 229,
    "stem": "battleground",
    "term": "battleground"
  },
  {
    "count": 227,
    "stem": "michigan",
    "term": "michigan"
  },
  {
    "count": 227,
    "stem": "william",
    "term": "william"
  },
  {
    "count": 227,
    "stem": "sector",
    "term": "sector"
  },
  {
    "count": 227,
    "stem": "contend",
    "term": "contends"
  },
  {
    "count": 226,
    "stem": "prosecut",
    "term": "prosecution"
  },
  {
    "count": 226,
    "stem": "bailout",
    "term": "bailout"
  },
  {
    "count": 225,
    "stem": "benghazi",
    "term": "benghazi"
  },
  {
    "count": 224,
    "stem": "default",
    "term": "default"
  },
  {
    "count": 223,
    "stem": "underscor",
    "term": "underscored"
  },
  {
    "count": 222,
    "stem": "eric",
    "term": "eric"
  },
  {
    "count": 222,
    "stem": "axelrod",
    "term": "axelrod"
  },
  {
    "count": 222,
    "stem": "christi",
    "term": "christie"
  },
  {
    "count": 222,
    "stem": "teacher",
    "term": "teachers"
  },
  {
    "count": 221,
    "stem": "india",
    "term": "india"
  },
  {
    "count": 221,
    "stem": "abort",
    "term": "abortion"
  },
  {
    "count": 221,
    "stem": "payrol",
    "term": "payroll"
  },
  {
    "count": 220,
    "stem": "deadlin",
    "term": "deadline"
  },
  {
    "count": 220,
    "stem": "victim",
    "term": "victims"
  },
  {
    "count": 220,
    "stem": "restor",
    "term": "restore"
  },
  {
    "count": 219,
    "stem": "gate",
    "term": "gates"
  },
  {
    "count": 219,
    "stem": "bachmann",
    "term": "bachmann"
  },
  {
    "count": 217,
    "stem": "rhetor",
    "term": "rhetoric"
  },
  {
    "count": 216,
    "stem": "huntsman",
    "term": "huntsman"
  },
  {
    "count": 216,
    "stem": "cabinet",
    "term": "cabinet"
  },
  {
    "count": 215,
    "stem": "profil",
    "term": "profile"
  },
  {
    "count": 214,
    "stem": "onlin",
    "term": "online"
  },
  {
    "count": 214,
    "stem": "forecast",
    "term": "forecast"
  },
  {
    "count": 213,
    "stem": "jersei",
    "term": "jersey"
  },
  {
    "count": 212,
    "stem": "guarante",
    "term": "guarantee"
  },
  {
    "count": 211,
    "stem": "armi",
    "term": "army"
  },
  {
    "count": 211,
    "stem": "emanuel",
    "term": "emanuel"
  },
  {
    "count": 210,
    "stem": "egyptian",
    "term": "egyptian"
  },
  {
    "count": 210,
    "stem": "cathol",
    "term": "catholic"
  },
  {
    "count": 210,
    "stem": "signatur",
    "term": "signature"
  },
  {
    "count": 210,
    "stem": "cancel",
    "term": "canceled"
  },
  {
    "count": 209,
    "stem": "counterterror",
    "term": "counterterrorism"
  },
  {
    "count": 208,
    "stem": "pakistani",
    "term": "pakistani"
  },
  {
    "count": 208,
    "stem": "gibb",
    "term": "gibbs"
  },
  {
    "count": 207,
    "stem": "dismiss",
    "term": "dismissed"
  },
  {
    "count": 206,
    "stem": "merkel",
    "term": "merkel"
  },
  {
    "count": 204,
    "stem": "avert",
    "term": "avert"
  },
  {
    "count": 204,
    "stem": "halt",
    "term": "halt"
  },
  {
    "count": 204,
    "stem": "contracept",
    "term": "contraception"
  },
  {
    "count": 203,
    "stem": "snowden",
    "term": "snowden"
  },
  {
    "count": 203,
    "stem": "mitch",
    "term": "mitch"
  },
  {
    "count": 202,
    "stem": "regulatori",
    "term": "regulatory"
  },
  {
    "count": 201,
    "stem": "weigh",
    "term": "weighing"
  },
  {
    "count": 201,
    "stem": "warren",
    "term": "warren"
  },
  {
    "count": 200,
    "stem": "taliban",
    "term": "taliban"
  },
  {
    "count": 199,
    "stem": "violat",
    "term": "violated"
  },
  {
    "count": 198,
    "stem": "export",
    "term": "exports"
  },
  {
    "count": 198,
    "stem": "pawlenti",
    "term": "pawlenty"
  },
  {
    "count": 197,
    "stem": "hurt",
    "term": "hurt"
  },
  {
    "count": 197,
    "stem": "crimin",
    "term": "criminal"
  },
  {
    "count": 197,
    "stem": "joe",
    "term": "joe"
  },
  {
    "count": 196,
    "stem": "donat",
    "term": "donations"
  },
  {
    "count": 196,
    "stem": "jewish",
    "term": "jewish"
  },
  {
    "count": 196,
    "stem": "soldier",
    "term": "soldiers"
  },
  {
    "count": 196,
    "stem": "franc",
    "term": "france"
  },
  {
    "count": 196,
    "stem": "unveil",
    "term": "unveiled"
  },
  {
    "count": 195,
    "stem": "kennedi",
    "term": "kennedy"
  },
  {
    "count": 195,
    "stem": "strengthen",
    "term": "strengthen"
  },
  {
    "count": 193,
    "stem": "portrai",
    "term": "portray"
  },
  {
    "count": 193,
    "stem": "comprehens",
    "term": "comprehensive"
  },
  {
    "count": 192,
    "stem": "innov",
    "term": "innovation"
  },
  {
    "count": 192,
    "stem": "outlin",
    "term": "outlined"
  },
  {
    "count": 192,
    "stem": "memo",
    "term": "memo"
  },
  {
    "count": 192,
    "stem": "journal",
    "term": "journal"
  },
  {
    "count": 191,
    "stem": "enact",
    "term": "enacted"
  },
  {
    "count": 191,
    "stem": "harvard",
    "term": "harvard"
  },
  {
    "count": 191,
    "stem": "greenhous",
    "term": "greenhouse"
  },
  {
    "count": 190,
    "stem": "undermin",
    "term": "undermine"
  },
  {
    "count": 190,
    "stem": "beij",
    "term": "beijing"
  },
  {
    "count": 189,
    "stem": "abc",
    "term": "abc"
  },
  {
    "count": 188,
    "stem": "richard",
    "term": "richard"
  },
  {
    "count": 188,
    "stem": "jame",
    "term": "james"
  },
  {
    "count": 187,
    "stem": "coal",
    "term": "coal"
  },
  {
    "count": 187,
    "stem": "captur",
    "term": "captured"
  },
  {
    "count": 187,
    "stem": "cuba",
    "term": "cuba"
  },
  {
    "count": 186,
    "stem": "taxpay",
    "term": "taxpayers"
  },
  {
    "count": 186,
    "stem": "surg",
    "term": "surge"
  },
  {
    "count": 185,
    "stem": "frank",
    "term": "frank"
  },
  {
    "count": 185,
    "stem": "hurrican",
    "term": "hurricane"
  },
  {
    "count": 185,
    "stem": "newt",
    "term": "newt"
  },
  {
    "count": 183,
    "stem": "consult",
    "term": "consulting"
  },
  {
    "count": 182,
    "stem": "trump",
    "term": "trump"
  },
  {
    "count": 180,
    "stem": "hagel",
    "term": "hagel"
  },
  {
    "count": 177,
    "stem": "skeptic",
    "term": "skeptical"
  },
  {
    "count": 177,
    "stem": "diplomaci",
    "term": "diplomacy"
  },
  {
    "count": 177,
    "stem": "boston",
    "term": "boston"
  },
  {
    "count": 176,
    "stem": "freez",
    "term": "freeze"
  },
  {
    "count": 176,
    "stem": "hospit",
    "term": "hospitals"
  },
  {
    "count": 175,
    "stem": "british",
    "term": "british"
  },
  {
    "count": 175,
    "stem": "pacif",
    "term": "pacific"
  },
  {
    "count": 174,
    "stem": "britain",
    "term": "britain"
  },
  {
    "count": 174,
    "stem": "japan",
    "term": "japan"
  },
  {
    "count": 174,
    "stem": "lobbyist",
    "term": "lobbyists"
  },
  {
    "count": 173,
    "stem": "fundament",
    "term": "fundamental"
  },
  {
    "count": 173,
    "stem": "certif",
    "term": "certificate"
  },
  {
    "count": 172,
    "stem": "sweep",
    "term": "sweeping"
  },
  {
    "count": 171,
    "stem": "exit",
    "term": "exit"
  },
  {
    "count": 170,
    "stem": "incumb",
    "term": "incumbent"
  },
  {
    "count": 170,
    "stem": "ticket",
    "term": "ticket"
  },
  {
    "count": 170,
    "stem": "san",
    "term": "san"
  },
  {
    "count": 170,
    "stem": "reli",
    "term": "rely"
  },
  {
    "count": 169,
    "stem": "pelosi",
    "term": "pelosi"
  },
  {
    "count": 168,
    "stem": "western",
    "term": "western"
  },
  {
    "count": 168,
    "stem": "radic",
    "term": "radical"
  },
  {
    "count": 168,
    "stem": "spill",
    "term": "spill"
  },
  {
    "count": 168,
    "stem": "photograph",
    "term": "photographs"
  },
  {
    "count": 168,
    "stem": "steven",
    "term": "steven"
  },
  {
    "count": 167,
    "stem": "denver",
    "term": "denver"
  },
  {
    "count": 167,
    "stem": "saudi",
    "term": "saudi"
  },
  {
    "count": 167,
    "stem": "cantor",
    "term": "cantor"
  },
  {
    "count": 167,
    "stem": "journalist",
    "term": "journalists"
  },
  {
    "count": 167,
    "stem": "keyston",
    "term": "keystone"
  },
  {
    "count": 167,
    "stem": "subsidi",
    "term": "subsidies"
  },
  {
    "count": 166,
    "stem": "deserv",
    "term": "deserves"
  },
  {
    "count": 166,
    "stem": "nbc",
    "term": "nbc"
  },
  {
    "count": 166,
    "stem": "solar",
    "term": "solar"
  },
  {
    "count": 165,
    "stem": "linkedin",
    "term": "linkedin"
  },
  {
    "count": 164,
    "stem": "lawsuit",
    "term": "lawsuit"
  },
  {
    "count": 164,
    "stem": "zone",
    "term": "zone"
  },
  {
    "count": 164,
    "stem": "chri",
    "term": "chris"
  },
  {
    "count": 164,
    "stem": "moscow",
    "term": "moscow"
  },
  {
    "count": 164,
    "stem": "ballot",
    "term": "ballot"
  },
  {
    "count": 164,
    "stem": "denounc",
    "term": "denounced"
  },
  {
    "count": 163,
    "stem": "concess",
    "term": "concessions"
  },
  {
    "count": 163,
    "stem": "bowl",
    "term": "bowles"
  },
  {
    "count": 163,
    "stem": "rice",
    "term": "rice"
  },
  {
    "count": 162,
    "stem": "investor",
    "term": "investors"
  },
  {
    "count": 162,
    "stem": "rescu",
    "term": "rescue"
  },
  {
    "count": 161,
    "stem": "resign",
    "term": "resignation"
  },
  {
    "count": 161,
    "stem": "turkei",
    "term": "turkey"
  },
  {
    "count": 161,
    "stem": "jon",
    "term": "jon"
  },
  {
    "count": 160,
    "stem": "wasn",
    "term": "wasn"
  },
  {
    "count": 160,
    "stem": "citizenship",
    "term": "citizenship"
  },
  {
    "count": 159,
    "stem": "meanwhil",
    "term": "meanwhile"
  },
  {
    "count": 159,
    "stem": "hostil",
    "term": "hostile"
  },
  {
    "count": 158,
    "stem": "digg",
    "term": "digg"
  },
  {
    "count": 157,
    "stem": "permalink",
    "term": "permalink"
  },
  {
    "count": 157,
    "stem": "cheer",
    "term": "cheers"
  },
  {
    "count": 157,
    "stem": "curb",
    "term": "curb"
  },
  {
    "count": 157,
    "stem": "mixx",
    "term": "mixx"
  },
  {
    "count": 156,
    "stem": "cairo",
    "term": "cairo"
  },
  {
    "count": 156,
    "stem": "sarkozi",
    "term": "sarkozy"
  },
  {
    "count": 156,
    "stem": "incent",
    "term": "incentives"
  },
  {
    "count": 155,
    "stem": "detent",
    "term": "detention"
  },
  {
    "count": 155,
    "stem": "strength",
    "term": "strength"
  },
  {
    "count": 155,
    "stem": "willing",
    "term": "willingness"
  },
  {
    "count": 154,
    "stem": "kick",
    "term": "kick"
  },
  {
    "count": 154,
    "stem": "counsel",
    "term": "counsel"
  },
  {
    "count": 154,
    "stem": "germani",
    "term": "germany"
  },
  {
    "count": 153,
    "stem": "tom",
    "term": "tom"
  },
  {
    "count": 152,
    "stem": "offens",
    "term": "offensive"
  },
  {
    "count": 152,
    "stem": "bashar",
    "term": "bashar"
  },
  {
    "count": 152,
    "stem": "foundat",
    "term": "foundation"
  },
  {
    "count": 152,
    "stem": "founder",
    "term": "founder"
  },
  {
    "count": 151,
    "stem": "basketbal",
    "term": "basketball"
  },
  {
    "count": 151,
    "stem": "jerusalem",
    "term": "jerusalem"
  },
  {
    "count": 151,
    "stem": "dalei",
    "term": "daley"
  },
  {
    "count": 150,
    "stem": "tap",
    "term": "tapped"
  },
  {
    "count": 150,
    "stem": "child",
    "term": "child"
  },
  {
    "count": 149,
    "stem": "disclosur",
    "term": "disclosures"
  },
  {
    "count": 149,
    "stem": "sarah",
    "term": "sarah"
  },
  {
    "count": 149,
    "stem": "loom",
    "term": "looming"
  },
  {
    "count": 148,
    "stem": "spokeswoman",
    "term": "spokeswoman"
  },
  {
    "count": 148,
    "stem": "vulner",
    "term": "vulnerable"
  },
  {
    "count": 148,
    "stem": "apolog",
    "term": "apologized"
  },
  {
    "count": 148,
    "stem": "stanc",
    "term": "stance"
  },
  {
    "count": 148,
    "stem": "abus",
    "term": "abuses"
  },
  {
    "count": 148,
    "stem": "partnership",
    "term": "partnership"
  },
  {
    "count": 148,
    "stem": "cliff",
    "term": "cliff"
  },
  {
    "count": 148,
    "stem": "winner",
    "term": "winner"
  },
  {
    "count": 147,
    "stem": "escal",
    "term": "escalating"
  },
  {
    "count": 147,
    "stem": "stabil",
    "term": "stability"
  },
  {
    "count": 147,
    "stem": "martin",
    "term": "martin"
  },
  {
    "count": 146,
    "stem": "gap",
    "term": "gap"
  },
  {
    "count": 145,
    "stem": "edward",
    "term": "edward"
  },
  {
    "count": 145,
    "stem": "geithner",
    "term": "geithner"
  },
  {
    "count": 145,
    "stem": "reluct",
    "term": "reluctant"
  },
  {
    "count": 144,
    "stem": "medal",
    "term": "medal"
  },
  {
    "count": 144,
    "stem": "korean",
    "term": "korean"
  },
  {
    "count": 144,
    "stem": "scott",
    "term": "scott"
  },
  {
    "count": 143,
    "stem": "collaps",
    "term": "collapse"
  },
  {
    "count": 142,
    "stem": "bain",
    "term": "bain"
  },
  {
    "count": 142,
    "stem": "jim",
    "term": "jim"
  },
  {
    "count": 142,
    "stem": "oversight",
    "term": "oversight"
  },
  {
    "count": 142,
    "stem": "embassi",
    "term": "embassy"
  },
  {
    "count": 142,
    "stem": "fals",
    "term": "false"
  },
  {
    "count": 142,
    "stem": "islam",
    "term": "islamic"
  },
  {
    "count": 142,
    "stem": "kentucki",
    "term": "kentucky"
  },
  {
    "count": 142,
    "stem": "critiqu",
    "term": "critique"
  },
  {
    "count": 141,
    "stem": "topic",
    "term": "topic"
  },
  {
    "count": 141,
    "stem": "admir",
    "term": "admiral"
  },
  {
    "count": 141,
    "stem": "sustain",
    "term": "sustained"
  },
  {
    "count": 140,
    "stem": "disclos",
    "term": "disclose"
  },
  {
    "count": 140,
    "stem": "intensifi",
    "term": "intensified"
  },
  {
    "count": 140,
    "stem": "tougher",
    "term": "tougher"
  },
  {
    "count": 139,
    "stem": "angel",
    "term": "angeles"
  },
  {
    "count": 139,
    "stem": "broadcast",
    "term": "broadcast"
  },
  {
    "count": 139,
    "stem": "ben",
    "term": "ben"
  },
  {
    "count": 139,
    "stem": "bolster",
    "term": "bolster"
  },
  {
    "count": 139,
    "stem": "outrag",
    "term": "outrage"
  },
  {
    "count": 139,
    "stem": "prosper",
    "term": "prosperity"
  },
  {
    "count": 139,
    "stem": "legaci",
    "term": "legacy"
  },
  {
    "count": 138,
    "stem": "holidai",
    "term": "holiday"
  },
  {
    "count": 138,
    "stem": "lincoln",
    "term": "lincoln"
  },
  {
    "count": 138,
    "stem": "christian",
    "term": "christian"
  },
  {
    "count": 137,
    "stem": "charlott",
    "term": "charlotte"
  },
  {
    "count": 137,
    "stem": "timothi",
    "term": "timothy"
  },
  {
    "count": 137,
    "stem": "cabl",
    "term": "cable"
  },
  {
    "count": 136,
    "stem": "classifi",
    "term": "classified"
  },
  {
    "count": 136,
    "stem": "carter",
    "term": "carter"
  },
  {
    "count": 136,
    "stem": "johnson",
    "term": "johnson"
  },
  {
    "count": 136,
    "stem": "fulfil",
    "term": "fulfill"
  },
  {
    "count": 135,
    "stem": "invok",
    "term": "invoked"
  },
  {
    "count": 135,
    "stem": "welfar",
    "term": "welfare"
  },
  {
    "count": 135,
    "stem": "deleg",
    "term": "delegates"
  },
  {
    "count": 135,
    "stem": "crime",
    "term": "crimes"
  },
  {
    "count": 135,
    "stem": "overal",
    "term": "overall"
  },
  {
    "count": 135,
    "stem": "krugman",
    "term": "krugman"
  },
  {
    "count": 134,
    "stem": "exempt",
    "term": "exempt"
  },
  {
    "count": 134,
    "stem": "currenc",
    "term": "currency"
  },
  {
    "count": 134,
    "stem": "thoma",
    "term": "thomas"
  },
  {
    "count": 133,
    "stem": "gop",
    "term": "gop"
  },
  {
    "count": 133,
    "stem": "columbia",
    "term": "columbia"
  },
  {
    "count": 133,
    "stem": "crackdown",
    "term": "crackdown"
  },
  {
    "count": 133,
    "stem": "usa",
    "term": "usa"
  },
  {
    "count": 133,
    "stem": "coordin",
    "term": "coordinated"
  },
  {
    "count": 133,
    "stem": "longtim",
    "term": "longtime"
  },
  {
    "count": 133,
    "stem": "complaint",
    "term": "complaints"
  },
  {
    "count": 132,
    "stem": "clash",
    "term": "clash"
  },
  {
    "count": 131,
    "stem": "peter",
    "term": "peter"
  },
  {
    "count": 131,
    "stem": "chrysler",
    "term": "chrysler"
  },
  {
    "count": 130,
    "stem": "split",
    "term": "split"
  },
  {
    "count": 130,
    "stem": "constitu",
    "term": "constituency"
  },
  {
    "count": 130,
    "stem": "sandi",
    "term": "sandy"
  },
  {
    "count": 130,
    "stem": "privaci",
    "term": "privacy"
  },
  {
    "count": 130,
    "stem": "boost",
    "term": "boost"
  },
  {
    "count": 129,
    "stem": "southern",
    "term": "southern"
  },
  {
    "count": 129,
    "stem": "mock",
    "term": "mocked"
  },
  {
    "count": 129,
    "stem": "stall",
    "term": "stalled"
  },
  {
    "count": 128,
    "stem": "nanci",
    "term": "nancy"
  },
  {
    "count": 128,
    "stem": "pivot",
    "term": "pivot"
  },
  {
    "count": 128,
    "stem": "reiter",
    "term": "reiterated"
  },
  {
    "count": 127,
    "stem": "billionair",
    "term": "billionaire"
  },
  {
    "count": 126,
    "stem": "digit",
    "term": "digital"
  },
  {
    "count": 126,
    "stem": "hint",
    "term": "hint"
  },
  {
    "count": 126,
    "stem": "plouff",
    "term": "plouffe"
  },
  {
    "count": 126,
    "stem": "brook",
    "term": "brooks"
  },
  {
    "count": 125,
    "stem": "navi",
    "term": "navy"
  },
  {
    "count": 125,
    "stem": "impass",
    "term": "impasse"
  },
  {
    "count": 125,
    "stem": "offshor",
    "term": "offshore"
  },
  {
    "count": 124,
    "stem": "spy",
    "term": "spy"
  },
  {
    "count": 124,
    "stem": "myanmar",
    "term": "myanmar"
  },
  {
    "count": 124,
    "stem": "tortur",
    "term": "torture"
  },
  {
    "count": 124,
    "stem": "jackson",
    "term": "jackson"
  },
  {
    "count": 123,
    "stem": "christma",
    "term": "christmas"
  },
  {
    "count": 123,
    "stem": "indonesia",
    "term": "indonesia"
  },
  {
    "count": 122,
    "stem": "mandela",
    "term": "mandela"
  },
  {
    "count": 122,
    "stem": "epa",
    "term": "epa"
  },
  {
    "count": 122,
    "stem": "counterpart",
    "term": "counterpart"
  },
  {
    "count": 122,
    "stem": "indiana",
    "term": "indiana"
  },
  {
    "count": 122,
    "stem": "appropri",
    "term": "appropriate"
  },
  {
    "count": 122,
    "stem": "solyndra",
    "term": "solyndra"
  },
  {
    "count": 121,
    "stem": "ambiti",
    "term": "ambitious"
  },
  {
    "count": 121,
    "stem": "childhood",
    "term": "childhood"
  },
  {
    "count": 121,
    "stem": "french",
    "term": "french"
  },
  {
    "count": 121,
    "stem": "brazil",
    "term": "brazil"
  },
  {
    "count": 121,
    "stem": "inherit",
    "term": "inherited"
  },
  {
    "count": 120,
    "stem": "deploi",
    "term": "deployed"
  },
  {
    "count": 120,
    "stem": "turnout",
    "term": "turnout"
  },
  {
    "count": 120,
    "stem": "mid",
    "term": "mid"
  },
  {
    "count": 120,
    "stem": "stump",
    "term": "stump"
  },
  {
    "count": 120,
    "stem": "interven",
    "term": "intervene"
  },
  {
    "count": 119,
    "stem": "milit",
    "term": "militants"
  },
  {
    "count": 119,
    "stem": "alleg",
    "term": "allegations"
  },
  {
    "count": 118,
    "stem": "transpar",
    "term": "transparency"
  },
  {
    "count": 118,
    "stem": "elizabeth",
    "term": "elizabeth"
  },
  {
    "count": 118,
    "stem": "detroit",
    "term": "detroit"
  },
  {
    "count": 118,
    "stem": "vega",
    "term": "vegas"
  },
  {
    "count": 118,
    "stem": "tim",
    "term": "tim"
  },
  {
    "count": 118,
    "stem": "homeown",
    "term": "homeowners"
  },
  {
    "count": 118,
    "stem": "marin",
    "term": "marine"
  },
  {
    "count": 118,
    "stem": "persist",
    "term": "persistent"
  },
  {
    "count": 118,
    "stem": "morsi",
    "term": "morsi"
  },
  {
    "count": 118,
    "stem": "upris",
    "term": "uprising"
  },
  {
    "count": 117,
    "stem": "tackl",
    "term": "tackle"
  },
  {
    "count": 117,
    "stem": "embarrass",
    "term": "embarrassing"
  },
  {
    "count": 117,
    "stem": "candidaci",
    "term": "candidacy"
  },
  {
    "count": 117,
    "stem": "unclear",
    "term": "unclear"
  },
  {
    "count": 117,
    "stem": "vladimir",
    "term": "vladimir"
  },
  {
    "count": 117,
    "stem": "monitor",
    "term": "monitoring"
  },
  {
    "count": 116,
    "stem": "muammar",
    "term": "muammar"
  },
  {
    "count": 116,
    "stem": "momentum",
    "term": "momentum"
  },
  {
    "count": 116,
    "stem": "conced",
    "term": "conceded"
  },
  {
    "count": 116,
    "stem": "seal",
    "term": "seal"
  },
  {
    "count": 116,
    "stem": "rouhani",
    "term": "rouhani"
  },
  {
    "count": 115,
    "stem": "anonym",
    "term": "anonymity"
  },
  {
    "count": 115,
    "stem": "jimmi",
    "term": "jimmy"
  },
  {
    "count": 115,
    "stem": "assail",
    "term": "assailed"
  },
  {
    "count": 115,
    "stem": "consensu",
    "term": "consensus"
  },
  {
    "count": 115,
    "stem": "departur",
    "term": "departure"
  },
  {
    "count": 115,
    "stem": "ronald",
    "term": "ronald"
  },
  {
    "count": 115,
    "stem": "hail",
    "term": "hailed"
  },
  {
    "count": 115,
    "stem": "lew",
    "term": "lew"
  },
  {
    "count": 115,
    "stem": "stewart",
    "term": "stewart"
  },
  {
    "count": 114,
    "stem": "stamp",
    "term": "stamp"
  },
  {
    "count": 114,
    "stem": "reuter",
    "term": "reuters"
  },
  {
    "count": 114,
    "stem": "unpopular",
    "term": "unpopular"
  },
  {
    "count": 114,
    "stem": "uncertainti",
    "term": "uncertainty"
  },
  {
    "count": 113,
    "stem": "panetta",
    "term": "panetta"
  },
  {
    "count": 113,
    "stem": "rev",
    "term": "rev"
  },
  {
    "count": 113,
    "stem": "manhattan",
    "term": "manhattan"
  },
  {
    "count": 113,
    "stem": "leverag",
    "term": "leverage"
  },
  {
    "count": 113,
    "stem": "northern",
    "term": "northern"
  },
  {
    "count": 113,
    "stem": "fierc",
    "term": "fierce"
  },
  {
    "count": 112,
    "stem": "weaken",
    "term": "weakened"
  },
  {
    "count": 112,
    "stem": "ron",
    "term": "ron"
  },
  {
    "count": 112,
    "stem": "emotion",
    "term": "emotional"
  },
  {
    "count": 112,
    "stem": "asian",
    "term": "asian"
  },
  {
    "count": 112,
    "stem": "tehran",
    "term": "tehran"
  },
  {
    "count": 112,
    "stem": "rove",
    "term": "rove"
  },
  {
    "count": 112,
    "stem": "crossroad",
    "term": "crossroads"
  },
  {
    "count": 111,
    "stem": "bruce",
    "term": "bruce"
  },
  {
    "count": 111,
    "stem": "gotten",
    "term": "gotten"
  },
  {
    "count": 111,
    "stem": "unilater",
    "term": "unilateral"
  },
  {
    "count": 111,
    "stem": "iraqi",
    "term": "iraqi"
  },
  {
    "count": 111,
    "stem": "scandal",
    "term": "scandal"
  },
  {
    "count": 111,
    "stem": "newtown",
    "term": "newtown"
  },
  {
    "count": 111,
    "stem": "mike",
    "term": "mike"
  },
  {
    "count": 110,
    "stem": "jinp",
    "term": "jinping"
  },
  {
    "count": 110,
    "stem": "spur",
    "term": "spur"
  },
  {
    "count": 110,
    "stem": "homeland",
    "term": "homeland"
  },
  {
    "count": 110,
    "stem": "minnesota",
    "term": "minnesota"
  },
  {
    "count": 110,
    "stem": "pollution",
    "term": "pollution"
  },
  {
    "count": 110,
    "stem": "applaus",
    "term": "applause"
  },
  {
    "count": 109,
    "stem": "envoi",
    "term": "envoy"
  },
  {
    "count": 109,
    "stem": "distract",
    "term": "distracted"
  },
  {
    "count": 109,
    "stem": "graham",
    "term": "graham"
  },
  {
    "count": 109,
    "stem": "inequ",
    "term": "inequality"
  },
  {
    "count": 109,
    "stem": "cuomo",
    "term": "cuomo"
  },
  {
    "count": 109,
    "stem": "cautiou",
    "term": "cautious"
  },
  {
    "count": 109,
    "stem": "donald",
    "term": "donald"
  },
  {
    "count": 109,
    "stem": "atlant",
    "term": "atlantic"
  },
  {
    "count": 108,
    "stem": "nationwid",
    "term": "nationwide"
  },
  {
    "count": 108,
    "stem": "acceler",
    "term": "accelerate"
  },
  {
    "count": 108,
    "stem": "bernank",
    "term": "bernanke"
  },
  {
    "count": 108,
    "stem": "german",
    "term": "german"
  },
  {
    "count": 108,
    "stem": "socialist",
    "term": "socialist"
  },
  {
    "count": 107,
    "stem": "specul",
    "term": "speculation"
  },
  {
    "count": 107,
    "stem": "dodd",
    "term": "dodd"
  },
  {
    "count": 107,
    "stem": "gen",
    "term": "gen"
  },
  {
    "count": 107,
    "stem": "hammer",
    "term": "hammer"
  },
  {
    "count": 107,
    "stem": "affili",
    "term": "affiliated"
  },
  {
    "count": 107,
    "stem": "react",
    "term": "reacted"
  },
  {
    "count": 106,
    "stem": "deduct",
    "term": "deductions"
  },
  {
    "count": 106,
    "stem": "pact",
    "term": "pact"
  },
  {
    "count": 106,
    "stem": "loophol",
    "term": "loopholes"
  },
  {
    "count": 105,
    "stem": "tech",
    "term": "tech"
  },
  {
    "count": 105,
    "stem": "insurg",
    "term": "insurgency"
  },
  {
    "count": 105,
    "stem": "walker",
    "term": "walker"
  },
  {
    "count": 104,
    "stem": "showdown",
    "term": "showdown"
  },
  {
    "count": 104,
    "stem": "slash",
    "term": "slashing"
  },
  {
    "count": 104,
    "stem": "mexican",
    "term": "mexican"
  },
  {
    "count": 104,
    "stem": "reassur",
    "term": "reassure"
  },
  {
    "count": 103,
    "stem": "col",
    "term": "col"
  },
  {
    "count": 103,
    "stem": "contractor",
    "term": "contractors"
  },
  {
    "count": 103,
    "stem": "asset",
    "term": "assets"
  },
  {
    "count": 103,
    "stem": "lee",
    "term": "lee"
  },
  {
    "count": 103,
    "stem": "forg",
    "term": "forge"
  },
  {
    "count": 102,
    "stem": "elig",
    "term": "eligible"
  },
  {
    "count": 102,
    "stem": "prosecutor",
    "term": "prosecutors"
  },
  {
    "count": 102,
    "stem": "compound",
    "term": "compound"
  },
  {
    "count": 102,
    "stem": "rebuild",
    "term": "rebuild"
  },
  {
    "count": 102,
    "stem": "brennan",
    "term": "brennan"
  },
  {
    "count": 102,
    "stem": "scientist",
    "term": "scientists"
  },
  {
    "count": 101,
    "stem": "bob",
    "term": "bob"
  },
  {
    "count": 101,
    "stem": "rein",
    "term": "rein"
  },
  {
    "count": 101,
    "stem": "judici",
    "term": "judicial"
  },
  {
    "count": 100,
    "stem": "scrutini",
    "term": "scrutiny"
  },
  {
    "count": 100,
    "stem": "alarm",
    "term": "alarm"
  },
  {
    "count": 100,
    "stem": "andrew",
    "term": "andrew"
  },
  {
    "count": 100,
    "stem": "lame",
    "term": "lame"
  },
  {
    "count": 99,
    "stem": "recov",
    "term": "recover"
  },
  {
    "count": 99,
    "stem": "buffett",
    "term": "buffett"
  },
  {
    "count": 98,
    "stem": "corrupt",
    "term": "corruption"
  },
  {
    "count": 98,
    "stem": "miami",
    "term": "miami"
  },
  {
    "count": 98,
    "stem": "fighter",
    "term": "fighters"
  },
  {
    "count": 98,
    "stem": "centrist",
    "term": "centrist"
  },
  {
    "count": 98,
    "stem": "rahm",
    "term": "rahm"
  },
  {
    "count": 98,
    "stem": "steve",
    "term": "steve"
  },
  {
    "count": 98,
    "stem": "tighten",
    "term": "tightening"
  },
  {
    "count": 98,
    "stem": "wari",
    "term": "wary"
  },
  {
    "count": 98,
    "stem": "maliki",
    "term": "maliki"
  },
  {
    "count": 98,
    "stem": "gasolin",
    "term": "gasoline"
  },
  {
    "count": 97,
    "stem": "perceiv",
    "term": "perceived"
  },
  {
    "count": 97,
    "stem": "obes",
    "term": "obesity"
  },
  {
    "count": 97,
    "stem": "fivethirtyeight",
    "term": "fivethirtyeight"
  },
  {
    "count": 97,
    "stem": "retreat",
    "term": "retreat"
  },
  {
    "count": 97,
    "stem": "territori",
    "term": "territory"
  },
  {
    "count": 97,
    "stem": "evolv",
    "term": "evolving"
  },
  {
    "count": 97,
    "stem": "ann",
    "term": "ann"
  },
  {
    "count": 97,
    "stem": "mill",
    "term": "mills"
  },
  {
    "count": 97,
    "stem": "chancellor",
    "term": "chancellor"
  },
  {
    "count": 96,
    "stem": "sport",
    "term": "sports"
  },
  {
    "count": 96,
    "stem": "reward",
    "term": "reward"
  },
  {
    "count": 96,
    "stem": "couldn",
    "term": "couldn"
  },
  {
    "count": 95,
    "stem": "revel",
    "term": "revelations"
  },
  {
    "count": 95,
    "stem": "gallup",
    "term": "gallup"
  },
  {
    "count": 95,
    "stem": "devast",
    "term": "devastating"
  },
  {
    "count": 95,
    "stem": "equiti",
    "term": "equity"
  },
  {
    "count": 95,
    "stem": "interrog",
    "term": "interrogation"
  },
  {
    "count": 95,
    "stem": "millionair",
    "term": "millionaires"
  },
  {
    "count": 94,
    "stem": "daniel",
    "term": "daniel"
  },
  {
    "count": 94,
    "stem": "canada",
    "term": "canada"
  },
  {
    "count": 94,
    "stem": "jintao",
    "term": "jintao"
  },
  {
    "count": 94,
    "stem": "seoul",
    "term": "seoul"
  },
  {
    "count": 94,
    "stem": "episod",
    "term": "episode"
  },
  {
    "count": 94,
    "stem": "rous",
    "term": "rouse"
  },
  {
    "count": 94,
    "stem": "pollster",
    "term": "pollster"
  },
  {
    "count": 93,
    "stem": "susan",
    "term": "susan"
  },
  {
    "count": 93,
    "stem": "smith",
    "term": "smith"
  },
  {
    "count": 93,
    "stem": "philadelphia",
    "term": "philadelphia"
  },
  {
    "count": 93,
    "stem": "haven",
    "term": "haven"
  },
  {
    "count": 93,
    "stem": "legitim",
    "term": "legitimate"
  },
  {
    "count": 93,
    "stem": "bankruptci",
    "term": "bankruptcy"
  },
  {
    "count": 93,
    "stem": "obamacar",
    "term": "obamacare"
  },
  {
    "count": 92,
    "stem": "reinforc",
    "term": "reinforce"
  },
  {
    "count": 92,
    "stem": "erdogan",
    "term": "erdogan"
  },
  {
    "count": 92,
    "stem": "plea",
    "term": "plea"
  },
  {
    "count": 92,
    "stem": "petraeu",
    "term": "petraeus"
  },
  {
    "count": 92,
    "stem": "london",
    "term": "london"
  },
  {
    "count": 92,
    "stem": "compel",
    "term": "compelling"
  },
  {
    "count": 92,
    "stem": "simpson",
    "term": "simpson"
  },
  {
    "count": 91,
    "stem": "jeff",
    "term": "jeff"
  },
  {
    "count": 91,
    "stem": "indian",
    "term": "indian"
  },
  {
    "count": 91,
    "stem": "fundrais",
    "term": "fundraiser"
  },
  {
    "count": 91,
    "stem": "hedg",
    "term": "hedge"
  },
  {
    "count": 91,
    "stem": "fla",
    "term": "fla"
  },
  {
    "count": 91,
    "stem": "circuit",
    "term": "circuit"
  },
  {
    "count": 91,
    "stem": "filibust",
    "term": "filibuster"
  },
  {
    "count": 91,
    "stem": "bishop",
    "term": "bishops"
  },
  {
    "count": 91,
    "stem": "enrol",
    "term": "enrollment"
  },
  {
    "count": 91,
    "stem": "sasha",
    "term": "sasha"
  },
  {
    "count": 90,
    "stem": "angela",
    "term": "angela"
  },
  {
    "count": 90,
    "stem": "stark",
    "term": "stark"
  },
  {
    "count": 90,
    "stem": "abba",
    "term": "abbas"
  },
  {
    "count": 90,
    "stem": "violent",
    "term": "violent"
  },
  {
    "count": 90,
    "stem": "arabia",
    "term": "arabia"
  },
  {
    "count": 90,
    "stem": "elit",
    "term": "elite"
  },
  {
    "count": 90,
    "stem": "disagre",
    "term": "disagree"
  },
  {
    "count": 90,
    "stem": "hamid",
    "term": "hamid"
  },
  {
    "count": 90,
    "stem": "sperl",
    "term": "sperling"
  },
  {
    "count": 90,
    "stem": "charl",
    "term": "charles"
  },
  {
    "count": 90,
    "stem": "unpreced",
    "term": "unprecedented"
  },
  {
    "count": 89,
    "stem": "rebuk",
    "term": "rebuke"
  },
  {
    "count": 89,
    "stem": "latin",
    "term": "latin"
  },
  {
    "count": 89,
    "stem": "eastern",
    "term": "eastern"
  },
  {
    "count": 89,
    "stem": "gifford",
    "term": "giffords"
  },
  {
    "count": 89,
    "stem": "congratul",
    "term": "congratulate"
  },
  {
    "count": 89,
    "stem": "implem",
    "term": "implement"
  },
  {
    "count": 89,
    "stem": "collin",
    "term": "collins"
  },
  {
    "count": 89,
    "stem": "airport",
    "term": "airport"
  },
  {
    "count": 88,
    "stem": "divers",
    "term": "diversity"
  },
  {
    "count": 88,
    "stem": "flag",
    "term": "flag"
  },
  {
    "count": 88,
    "stem": "congressman",
    "term": "congressman"
  },
  {
    "count": 88,
    "stem": "contenti",
    "term": "contentious"
  },
  {
    "count": 88,
    "stem": "moham",
    "term": "mohammed"
  },
  {
    "count": 88,
    "stem": "referendum",
    "term": "referendum"
  },
  {
    "count": 88,
    "stem": "polar",
    "term": "polarizing"
  },
  {
    "count": 88,
    "stem": "tucson",
    "term": "tucson"
  },
  {
    "count": 88,
    "stem": "colombia",
    "term": "colombia"
  },
  {
    "count": 87,
    "stem": "ambition",
    "term": "ambitions"
  },
  {
    "count": 87,
    "stem": "auster",
    "term": "austerity"
  },
  {
    "count": 86,
    "stem": "downgrad",
    "term": "downgrade"
  },
  {
    "count": 86,
    "stem": "nobel",
    "term": "nobel"
  },
  {
    "count": 86,
    "stem": "appointe",
    "term": "appointees"
  },
  {
    "count": 86,
    "stem": "shrink",
    "term": "shrinking"
  },
  {
    "count": 86,
    "stem": "roosevelt",
    "term": "roosevelt"
  },
  {
    "count": 86,
    "stem": "tent",
    "term": "tentative"
  },
  {
    "count": 86,
    "stem": "youth",
    "term": "youth"
  },
  {
    "count": 86,
    "stem": "corp",
    "term": "corps"
  },
  {
    "count": 85,
    "stem": "unconstitut",
    "term": "unconstitutional"
  },
  {
    "count": 85,
    "stem": "enrich",
    "term": "enrichment"
  },
  {
    "count": 85,
    "stem": "academi",
    "term": "academy"
  },
  {
    "count": 85,
    "stem": "lesbian",
    "term": "lesbian"
  },
  {
    "count": 85,
    "stem": "disrupt",
    "term": "disrupt"
  },
  {
    "count": 85,
    "stem": "energ",
    "term": "energized"
  },
  {
    "count": 85,
    "stem": "adversari",
    "term": "adversaries"
  },
  {
    "count": 85,
    "stem": "cleveland",
    "term": "cleveland"
  },
  {
    "count": 85,
    "stem": "jobless",
    "term": "jobless"
  },
  {
    "count": 85,
    "stem": "politico",
    "term": "politico"
  },
  {
    "count": 85,
    "stem": "koch",
    "term": "koch"
  },
  {
    "count": 85,
    "stem": "foreclosur",
    "term": "foreclosure"
  },
  {
    "count": 85,
    "stem": "ali",
    "term": "ali"
  },
  {
    "count": 85,
    "stem": "limbaugh",
    "term": "limbaugh"
  },
  {
    "count": 84,
    "stem": "maryland",
    "term": "maryland"
  },
  {
    "count": 84,
    "stem": "overse",
    "term": "oversee"
  },
  {
    "count": 84,
    "stem": "airstrik",
    "term": "airstrikes"
  },
  {
    "count": 84,
    "stem": "sensibl",
    "term": "sensible"
  },
  {
    "count": 84,
    "stem": "rhode",
    "term": "rhodes"
  },
  {
    "count": 84,
    "stem": "brain",
    "term": "brain"
  },
  {
    "count": 84,
    "stem": "demograph",
    "term": "demographic"
  },
  {
    "count": 84,
    "stem": "dialogu",
    "term": "dialogue"
  },
  {
    "count": 84,
    "stem": "centerpiec",
    "term": "centerpiece"
  },
  {
    "count": 84,
    "stem": "assassin",
    "term": "assassination"
  },
  {
    "count": 84,
    "stem": "advocaci",
    "term": "advocacy"
  },
  {
    "count": 84,
    "stem": "stephen",
    "term": "stephen"
  },
  {
    "count": 83,
    "stem": "unfair",
    "term": "unfair"
  },
  {
    "count": 83,
    "stem": "malia",
    "term": "malia"
  },
  {
    "count": 83,
    "stem": "oklahoma",
    "term": "oklahoma"
  },
  {
    "count": 83,
    "stem": "standoff",
    "term": "standoff"
  },
  {
    "count": 83,
    "stem": "glenn",
    "term": "glenn"
  },
  {
    "count": 83,
    "stem": "kenya",
    "term": "kenya"
  },
  {
    "count": 83,
    "stem": "wikileak",
    "term": "wikileaks"
  },
  {
    "count": 83,
    "stem": "unemploi",
    "term": "unemployed"
  },
  {
    "count": 83,
    "stem": "blunt",
    "term": "blunt"
  },
  {
    "count": 83,
    "stem": "medvedev",
    "term": "medvedev"
  },
  {
    "count": 83,
    "stem": "broker",
    "term": "broker"
  },
  {
    "count": 82,
    "stem": "awlaki",
    "term": "awlaki"
  },
  {
    "count": 82,
    "stem": "scrambl",
    "term": "scrambling"
  },
  {
    "count": 82,
    "stem": "drag",
    "term": "dragged"
  },
  {
    "count": 82,
    "stem": "rubio",
    "term": "rubio"
  },
  {
    "count": 82,
    "stem": "wrap",
    "term": "wrapped"
  },
  {
    "count": 82,
    "stem": "patriot",
    "term": "patriot"
  },
  {
    "count": 82,
    "stem": "suburb",
    "term": "suburbs"
  },
  {
    "count": 81,
    "stem": "silicon",
    "term": "silicon"
  },
  {
    "count": 81,
    "stem": "outreach",
    "term": "outreach"
  },
  {
    "count": 81,
    "stem": "chuck",
    "term": "chuck"
  },
  {
    "count": 81,
    "stem": "waiver",
    "term": "waivers"
  },
  {
    "count": 81,
    "stem": "connecticut",
    "term": "connecticut"
  },
  {
    "count": 81,
    "stem": "doug",
    "term": "doug"
  },
  {
    "count": 81,
    "stem": "wealthiest",
    "term": "wealthiest"
  },
  {
    "count": 80,
    "stem": "prohibit",
    "term": "prohibit"
  },
  {
    "count": 80,
    "stem": "pardon",
    "term": "pardon"
  },
  {
    "count": 80,
    "stem": "moratorium",
    "term": "moratorium"
  },
  {
    "count": 80,
    "stem": "beneficiari",
    "term": "beneficiaries"
  },
  {
    "count": 80,
    "stem": "sudan",
    "term": "sudan"
  },
  {
    "count": 80,
    "stem": "earmark",
    "term": "earmarks"
  },
  {
    "count": 79,
    "stem": "successor",
    "term": "successor"
  },
  {
    "count": 79,
    "stem": "disapprov",
    "term": "disapprove"
  },
  {
    "count": 79,
    "stem": "leagu",
    "term": "league"
  },
  {
    "count": 79,
    "stem": "prod",
    "term": "prodding"
  },
  {
    "count": 79,
    "stem": "pew",
    "term": "pew"
  },
  {
    "count": 79,
    "stem": "donilon",
    "term": "donilon"
  },
  {
    "count": 79,
    "stem": "backdrop",
    "term": "backdrop"
  },
  {
    "count": 79,
    "stem": "undecid",
    "term": "undecided"
  },
  {
    "count": 78,
    "stem": "aspir",
    "term": "aspirations"
  },
  {
    "count": 78,
    "stem": "jonathan",
    "term": "jonathan"
  },
  {
    "count": 78,
    "stem": "wright",
    "term": "wright"
  },
  {
    "count": 78,
    "stem": "reset",
    "term": "reset"
  },
  {
    "count": 78,
    "stem": "viewer",
    "term": "viewers"
  },
  {
    "count": 78,
    "stem": "georgia",
    "term": "georgia"
  },
  {
    "count": 78,
    "stem": "apologi",
    "term": "apology"
  },
  {
    "count": 77,
    "stem": "banker",
    "term": "bankers"
  },
  {
    "count": 77,
    "stem": "slogan",
    "term": "slogan"
  },
  {
    "count": 77,
    "stem": "extremist",
    "term": "extremists"
  },
  {
    "count": 77,
    "stem": "massacr",
    "term": "massacre"
  },
  {
    "count": 77,
    "stem": "fraud",
    "term": "fraud"
  },
  {
    "count": 77,
    "stem": "campu",
    "term": "campus"
  },
  {
    "count": 77,
    "stem": "contributor",
    "term": "contributors"
  },
  {
    "count": 77,
    "stem": "intellectu",
    "term": "intellectual"
  },
  {
    "count": 77,
    "stem": "bulli",
    "term": "bully"
  },
  {
    "count": 77,
    "stem": "penalti",
    "term": "penalties"
  },
  {
    "count": 76,
    "stem": "recognit",
    "term": "recognition"
  },
  {
    "count": 76,
    "stem": "bahrain",
    "term": "bahrain"
  },
  {
    "count": 76,
    "stem": "cuban",
    "term": "cuban"
  },
  {
    "count": 76,
    "stem": "versu",
    "term": "versus"
  },
  {
    "count": 76,
    "stem": "deepen",
    "term": "deepen"
  },
  {
    "count": 76,
    "stem": "birther",
    "term": "birther"
  },
  {
    "count": 75,
    "stem": "spotlight",
    "term": "spotlight"
  },
  {
    "count": 75,
    "stem": "robust",
    "term": "robust"
  },
  {
    "count": 75,
    "stem": "kim",
    "term": "kim"
  },
  {
    "count": 75,
    "stem": "pois",
    "term": "poised"
  },
  {
    "count": 75,
    "stem": "afterward",
    "term": "afterward"
  },
  {
    "count": 75,
    "stem": "brand",
    "term": "brand"
  },
  {
    "count": 75,
    "stem": "caution",
    "term": "caution"
  },
  {
    "count": 75,
    "stem": "gase",
    "term": "gases"
  },
  {
    "count": 75,
    "stem": "brutal",
    "term": "brutal"
  },
  {
    "count": 74,
    "stem": "jarrett",
    "term": "jarrett"
  },
  {
    "count": 74,
    "stem": "applaud",
    "term": "applauded"
  },
  {
    "count": 74,
    "stem": "chairwoman",
    "term": "chairwoman"
  },
  {
    "count": 74,
    "stem": "messina",
    "term": "messina"
  },
  {
    "count": 74,
    "stem": "attribut",
    "term": "attributed"
  },
  {
    "count": 74,
    "stem": "harsh",
    "term": "harsh"
  },
  {
    "count": 74,
    "stem": "tampa",
    "term": "tampa"
  },
  {
    "count": 74,
    "stem": "alabama",
    "term": "alabama"
  },
  {
    "count": 74,
    "stem": "kansa",
    "term": "kansas"
  },
  {
    "count": 74,
    "stem": "shield",
    "term": "shield"
  },
  {
    "count": 74,
    "stem": "premium",
    "term": "premiums"
  },
  {
    "count": 74,
    "stem": "inflat",
    "term": "inflation"
  },
  {
    "count": 73,
    "stem": "agricultur",
    "term": "agriculture"
  },
  {
    "count": 73,
    "stem": "gore",
    "term": "gore"
  },
  {
    "count": 73,
    "stem": "oust",
    "term": "oust"
  },
  {
    "count": 73,
    "stem": "portrait",
    "term": "portrait"
  },
  {
    "count": 73,
    "stem": "presumpt",
    "term": "presumptive"
  },
  {
    "count": 73,
    "stem": "tweet",
    "term": "tweet"
  },
  {
    "count": 73,
    "stem": "translat",
    "term": "translate"
  },
  {
    "count": 73,
    "stem": "lede",
    "term": "lede"
  },
  {
    "count": 73,
    "stem": "populist",
    "term": "populist"
  },
  {
    "count": 73,
    "stem": "museum",
    "term": "museum"
  },
  {
    "count": 73,
    "stem": "hosni",
    "term": "hosni"
  },
  {
    "count": 73,
    "stem": "karl",
    "term": "karl"
  },
  {
    "count": 73,
    "stem": "issa",
    "term": "issa"
  },
  {
    "count": 73,
    "stem": "martha",
    "term": "martha"
  },
  {
    "count": 73,
    "stem": "mississippi",
    "term": "mississippi"
  },
  {
    "count": 73,
    "stem": "davi",
    "term": "davis"
  },
  {
    "count": 73,
    "stem": "avenu",
    "term": "avenue"
  },
  {
    "count": 72,
    "stem": "vietnam",
    "term": "vietnam"
  },
  {
    "count": 72,
    "stem": "prayer",
    "term": "prayer"
  },
  {
    "count": 72,
    "stem": "gut",
    "term": "gut"
  },
  {
    "count": 72,
    "stem": "youtub",
    "term": "youtube"
  },
  {
    "count": 72,
    "stem": "slam",
    "term": "slam"
  },
  {
    "count": 72,
    "stem": "pragmat",
    "term": "pragmatic"
  },
  {
    "count": 72,
    "stem": "sotomayor",
    "term": "sotomayor"
  },
  {
    "count": 72,
    "stem": "influenti",
    "term": "influential"
  },
  {
    "count": 72,
    "stem": "framework",
    "term": "framework"
  },
  {
    "count": 72,
    "stem": "jeffrei",
    "term": "jeffrey"
  },
  {
    "count": 72,
    "stem": "alaska",
    "term": "alaska"
  },
  {
    "count": 72,
    "stem": "timet",
    "term": "timetable"
  },
  {
    "count": 71,
    "stem": "awkward",
    "term": "awkward"
  },
  {
    "count": 71,
    "stem": "rousseff",
    "term": "rousseff"
  },
  {
    "count": 71,
    "stem": "missouri",
    "term": "missouri"
  },
  {
    "count": 71,
    "stem": "queen",
    "term": "queen"
  },
  {
    "count": 71,
    "stem": "recruit",
    "term": "recruited"
  },
  {
    "count": 71,
    "stem": "stir",
    "term": "stirring"
  },
  {
    "count": 71,
    "stem": "birthdai",
    "term": "birthday"
  },
  {
    "count": 71,
    "stem": "blagojevich",
    "term": "blagojevich"
  },
  {
    "count": 71,
    "stem": "sidelin",
    "term": "sidelines"
  },
  {
    "count": 71,
    "stem": "allen",
    "term": "allen"
  },
  {
    "count": 71,
    "stem": "adam",
    "term": "adam"
  },
  {
    "count": 71,
    "stem": "arsen",
    "term": "arsenal"
  },
  {
    "count": 71,
    "stem": "univis",
    "term": "univision"
  },
  {
    "count": 71,
    "stem": "discrimin",
    "term": "discrimination"
  },
  {
    "count": 71,
    "stem": "nicola",
    "term": "nicolas"
  },
  {
    "count": 70,
    "stem": "provok",
    "term": "provoke"
  },
  {
    "count": 70,
    "stem": "flaw",
    "term": "flawed"
  },
  {
    "count": 70,
    "stem": "flood",
    "term": "flood"
  },
  {
    "count": 70,
    "stem": "berlin",
    "term": "berlin"
  },
  {
    "count": 70,
    "stem": "conn",
    "term": "conn"
  },
  {
    "count": 70,
    "stem": "postpon",
    "term": "postponed"
  },
  {
    "count": 70,
    "stem": "kabul",
    "term": "kabul"
  },
  {
    "count": 70,
    "stem": "scientif",
    "term": "scientific"
  },
  {
    "count": 70,
    "stem": "overturn",
    "term": "overturn"
  },
  {
    "count": 70,
    "stem": "closest",
    "term": "closest"
  },
  {
    "count": 70,
    "stem": "dan",
    "term": "dan"
  },
  {
    "count": 70,
    "stem": "stalem",
    "term": "stalemate"
  },
  {
    "count": 70,
    "stem": "dictat",
    "term": "dictator"
  },
  {
    "count": 70,
    "stem": "surrog",
    "term": "surrogates"
  },
  {
    "count": 70,
    "stem": "maneuv",
    "term": "maneuvering"
  },
  {
    "count": 70,
    "stem": "baker",
    "term": "baker"
  },
  {
    "count": 70,
    "stem": "narrowli",
    "term": "narrowly"
  },
  {
    "count": 70,
    "stem": "reopen",
    "term": "reopen"
  },
  {
    "count": 70,
    "stem": "endur",
    "term": "enduring"
  },
  {
    "count": 70,
    "stem": "pundit",
    "term": "pundits"
  },
  {
    "count": 69,
    "stem": "jacob",
    "term": "jacob"
  },
  {
    "count": 69,
    "stem": "tenur",
    "term": "tenure"
  },
  {
    "count": 69,
    "stem": "unifi",
    "term": "unified"
  },
  {
    "count": 69,
    "stem": "unfold",
    "term": "unfolding"
  },
  {
    "count": 69,
    "stem": "landmark",
    "term": "landmark"
  },
  {
    "count": 69,
    "stem": "optimist",
    "term": "optimistic"
  },
  {
    "count": 69,
    "stem": "deem",
    "term": "deemed"
  },
  {
    "count": 69,
    "stem": "ross",
    "term": "ross"
  },
  {
    "count": 69,
    "stem": "podesta",
    "term": "podesta"
  },
  {
    "count": 69,
    "stem": "blast",
    "term": "blasts"
  },
  {
    "count": 69,
    "stem": "traffick",
    "term": "trafficking"
  },
  {
    "count": 69,
    "stem": "kain",
    "term": "kaine"
  },
  {
    "count": 69,
    "stem": "sen",
    "term": "sen"
  },
  {
    "count": 69,
    "stem": "await",
    "term": "awaited"
  },
  {
    "count": 69,
    "stem": "tout",
    "term": "touted"
  },
  {
    "count": 69,
    "stem": "helicopt",
    "term": "helicopter"
  },
  {
    "count": 69,
    "stem": "reshap",
    "term": "reshaping"
  },
  {
    "count": 68,
    "stem": "revis",
    "term": "revised"
  },
  {
    "count": 68,
    "stem": "humanitarian",
    "term": "humanitarian"
  },
  {
    "count": 68,
    "stem": "foster",
    "term": "foster"
  },
  {
    "count": 68,
    "stem": "abdullah",
    "term": "abdullah"
  },
  {
    "count": 68,
    "stem": "environmentalist",
    "term": "environmentalists"
  },
  {
    "count": 68,
    "stem": "dismantl",
    "term": "dismantle"
  },
  {
    "count": 68,
    "stem": "defer",
    "term": "deferred"
  },
  {
    "count": 68,
    "stem": "urgenc",
    "term": "urgency"
  },
  {
    "count": 68,
    "stem": "googl",
    "term": "google"
  },
  {
    "count": 68,
    "stem": "offset",
    "term": "offset"
  },
  {
    "count": 67,
    "stem": "teach",
    "term": "teaching"
  },
  {
    "count": 67,
    "stem": "alongsid",
    "term": "alongside"
  },
  {
    "count": 67,
    "stem": "kenyan",
    "term": "kenyan"
  },
  {
    "count": 67,
    "stem": "bounc",
    "term": "bounce"
  },
  {
    "count": 67,
    "stem": "don't",
    "term": "don't"
  },
  {
    "count": 67,
    "stem": "runner",
    "term": "runner"
  },
  {
    "count": 67,
    "stem": "clip",
    "term": "clip"
  },
  {
    "count": 67,
    "stem": "utah",
    "term": "utah"
  },
  {
    "count": 67,
    "stem": "francisco",
    "term": "francisco"
  },
  {
    "count": 67,
    "stem": "inquiri",
    "term": "inquiry"
  },
  {
    "count": 66,
    "stem": "oath",
    "term": "oath"
  },
  {
    "count": 66,
    "stem": "columbu",
    "term": "columbus"
  },
  {
    "count": 66,
    "stem": "larri",
    "term": "larry"
  },
  {
    "count": 66,
    "stem": "sequestr",
    "term": "sequestration"
  },
  {
    "count": 66,
    "stem": "aftermath",
    "term": "aftermath"
  },
  {
    "count": 66,
    "stem": "cancer",
    "term": "cancer"
  },
  {
    "count": 66,
    "stem": "bundler",
    "term": "bundlers"
  },
  {
    "count": 66,
    "stem": "uphold",
    "term": "uphold"
  },
  {
    "count": 66,
    "stem": "depict",
    "term": "depicted"
  },
  {
    "count": 66,
    "stem": "jordan",
    "term": "jordan"
  },
  {
    "count": 66,
    "stem": "regardless",
    "term": "regardless"
  },
  {
    "count": 66,
    "stem": "tens",
    "term": "tense"
  },
  {
    "count": 66,
    "stem": "crowlei",
    "term": "crowley"
  },
  {
    "count": 66,
    "stem": "privileg",
    "term": "privilege"
  },
  {
    "count": 66,
    "stem": "resort",
    "term": "resort"
  },
  {
    "count": 66,
    "stem": "pump",
    "term": "pump"
  },
  {
    "count": 65,
    "stem": "brooklyn",
    "term": "brooklyn"
  },
  {
    "count": 65,
    "stem": "mari",
    "term": "mary"
  },
  {
    "count": 65,
    "stem": "diminish",
    "term": "diminished"
  },
  {
    "count": 65,
    "stem": "australia",
    "term": "australia"
  },
  {
    "count": 65,
    "stem": "olymp",
    "term": "olympic"
  },
  {
    "count": 65,
    "stem": "guantanamo",
    "term": "guantanamo"
  },
  {
    "count": 65,
    "stem": "wealth",
    "term": "wealth"
  },
  {
    "count": 65,
    "stem": "vineyard",
    "term": "vineyard"
  },
  {
    "count": 65,
    "stem": "jone",
    "term": "jones"
  },
  {
    "count": 65,
    "stem": "aircraft",
    "term": "aircraft"
  },
  {
    "count": 65,
    "stem": "crise",
    "term": "crises"
  },
  {
    "count": 65,
    "stem": "opt",
    "term": "opted"
  },
  {
    "count": 65,
    "stem": "cordrai",
    "term": "cordray"
  },
  {
    "count": 65,
    "stem": "advisori",
    "term": "advisory"
  },
  {
    "count": 65,
    "stem": "hostag",
    "term": "hostage"
  },
  {
    "count": 65,
    "stem": "non",
    "term": "non"
  },
  {
    "count": 65,
    "stem": "tribun",
    "term": "tribunals"
  },
  {
    "count": 65,
    "stem": "vagu",
    "term": "vague"
  },
  {
    "count": 65,
    "stem": "nonprofit",
    "term": "nonprofit"
  },
  {
    "count": 64,
    "stem": "endang",
    "term": "endangered"
  },
  {
    "count": 64,
    "stem": "clarifi",
    "term": "clarify"
  },
  {
    "count": 64,
    "stem": "turmoil",
    "term": "turmoil"
  },
  {
    "count": 64,
    "stem": "enhanc",
    "term": "enhanced"
  },
  {
    "count": 64,
    "stem": "gaza",
    "term": "gaza"
  },
  {
    "count": 64,
    "stem": "backer",
    "term": "backers"
  },
  {
    "count": 64,
    "stem": "leon",
    "term": "leon"
  },
  {
    "count": 64,
    "stem": "pursuit",
    "term": "pursuit"
  },
  {
    "count": 64,
    "stem": "roger",
    "term": "roger"
  },
  {
    "count": 64,
    "stem": "provoc",
    "term": "provocative"
  },
  {
    "count": 64,
    "stem": "stimul",
    "term": "stimulate"
  },
  {
    "count": 63,
    "stem": "unaccept",
    "term": "unacceptable"
  },
  {
    "count": 63,
    "stem": "obstacl",
    "term": "obstacles"
  },
  {
    "count": 63,
    "stem": "nonetheless",
    "term": "nonetheless"
  },
  {
    "count": 63,
    "stem": "websit",
    "term": "website"
  },
  {
    "count": 63,
    "stem": "nytim",
    "term": "nytimes"
  },
  {
    "count": 63,
    "stem": "conven",
    "term": "convened"
  },
  {
    "count": 63,
    "stem": "lament",
    "term": "lamented"
  },
  {
    "count": 63,
    "stem": "bypass",
    "term": "bypass"
  },
  {
    "count": 63,
    "stem": "offend",
    "term": "offended"
  },
  {
    "count": 63,
    "stem": "huckabe",
    "term": "huckabee"
  },
  {
    "count": 63,
    "stem": "chapter",
    "term": "chapter"
  },
  {
    "count": 63,
    "stem": "reaffirm",
    "term": "reaffirmed"
  },
  {
    "count": 63,
    "stem": "peril",
    "term": "peril"
  },
  {
    "count": 63,
    "stem": "math",
    "term": "math"
  },
  {
    "count": 63,
    "stem": "spanish",
    "term": "spanish"
  },
  {
    "count": 63,
    "stem": "arrai",
    "term": "array"
  },
  {
    "count": 62,
    "stem": "lend",
    "term": "lending"
  },
  {
    "count": 62,
    "stem": "msnbc",
    "term": "msnbc"
  },
  {
    "count": 62,
    "stem": "lowest",
    "term": "lowest"
  },
  {
    "count": 62,
    "stem": "regret",
    "term": "regret"
  },
  {
    "count": 62,
    "stem": "rage",
    "term": "rage"
  },
  {
    "count": 62,
    "stem": "affirm",
    "term": "affirmed"
  },
  {
    "count": 62,
    "stem": "matchup",
    "term": "matchup"
  },
  {
    "count": 62,
    "stem": "enlist",
    "term": "enlisted"
  },
  {
    "count": 62,
    "stem": "undercut",
    "term": "undercut"
  },
  {
    "count": 62,
    "stem": "repress",
    "term": "repression"
  },
  {
    "count": 62,
    "stem": "reson",
    "term": "resonate"
  },
  {
    "count": 62,
    "stem": "erupt",
    "term": "erupted"
  },
  {
    "count": 61,
    "stem": "subsid",
    "term": "subsidized"
  },
  {
    "count": 61,
    "stem": "memorandum",
    "term": "memorandum"
  },
  {
    "count": 61,
    "stem": "unrest",
    "term": "unrest"
  },
  {
    "count": 61,
    "stem": "fragil",
    "term": "fragile"
  },
  {
    "count": 61,
    "stem": "furiou",
    "term": "furious"
  },
  {
    "count": 61,
    "stem": "wise",
    "term": "wise"
  },
  {
    "count": 61,
    "stem": "nonpartisan",
    "term": "nonpartisan"
  },
  {
    "count": 61,
    "stem": "fade",
    "term": "faded"
  },
  {
    "count": 61,
    "stem": "disagr",
    "term": "disagreement"
  },
  {
    "count": 61,
    "stem": "uranium",
    "term": "uranium"
  },
  {
    "count": 61,
    "stem": "immin",
    "term": "imminent"
  },
  {
    "count": 61,
    "stem": "frai",
    "term": "fray"
  },
  {
    "count": 61,
    "stem": "plead",
    "term": "pleaded"
  },
  {
    "count": 61,
    "stem": "propel",
    "term": "propelled"
  },
  {
    "count": 61,
    "stem": "vacanc",
    "term": "vacancies"
  },
  {
    "count": 61,
    "stem": "defi",
    "term": "defy"
  },
  {
    "count": 61,
    "stem": "recount",
    "term": "recounted"
  },
  {
    "count": 60,
    "stem": "parliam",
    "term": "parliament"
  },
  {
    "count": 60,
    "stem": "gram",
    "term": "grams"
  },
  {
    "count": 60,
    "stem": "secreci",
    "term": "secrecy"
  },
  {
    "count": 60,
    "stem": "skip",
    "term": "skipped"
  },
  {
    "count": 60,
    "stem": "sequest",
    "term": "sequester"
  },
  {
    "count": 60,
    "stem": "bow",
    "term": "bow"
  },
  {
    "count": 60,
    "stem": "empow",
    "term": "empowered"
  },
  {
    "count": 60,
    "stem": "ordinari",
    "term": "ordinary"
  },
  {
    "count": 60,
    "stem": "spectrum",
    "term": "spectrum"
  },
  {
    "count": 59,
    "stem": "hug",
    "term": "hug"
  },
  {
    "count": 59,
    "stem": "castig",
    "term": "castigated"
  },
  {
    "count": 59,
    "stem": "earnest",
    "term": "earnest"
  },
  {
    "count": 59,
    "stem": "soar",
    "term": "soaring"
  },
  {
    "count": 59,
    "stem": "blogger",
    "term": "blogger"
  },
  {
    "count": 59,
    "stem": "mahmoud",
    "term": "mahmoud"
  },
  {
    "count": 59,
    "stem": "marijuana",
    "term": "marijuana"
  },
  {
    "count": 59,
    "stem": "sworn",
    "term": "sworn"
  },
  {
    "count": 59,
    "stem": "buzz",
    "term": "buzz"
  },
  {
    "count": 59,
    "stem": "caucus",
    "term": "caucuses"
  },
  {
    "count": 59,
    "stem": "prescript",
    "term": "prescription"
  },
  {
    "count": 59,
    "stem": "client",
    "term": "clients"
  },
  {
    "count": 59,
    "stem": "luther",
    "term": "luther"
  },
  {
    "count": 59,
    "stem": "outsourc",
    "term": "outsourcing"
  },
  {
    "count": 59,
    "stem": "articul",
    "term": "articulate"
  },
  {
    "count": 59,
    "stem": "indict",
    "term": "indictment"
  },
  {
    "count": 59,
    "stem": "petersburg",
    "term": "petersburg"
  },
  {
    "count": 59,
    "stem": "pfeiffer",
    "term": "pfeiffer"
  },
  {
    "count": 59,
    "stem": "toxic",
    "term": "toxic"
  },
  {
    "count": 59,
    "stem": "chenei",
    "term": "cheney"
  },
  {
    "count": 59,
    "stem": "propon",
    "term": "proponents"
  },
  {
    "count": 59,
    "stem": "jack",
    "term": "jack"
  },
  {
    "count": 59,
    "stem": "brotherhood",
    "term": "brotherhood"
  },
  {
    "count": 59,
    "stem": "leas",
    "term": "leases"
  },
  {
    "count": 59,
    "stem": "islamist",
    "term": "islamist"
  },
  {
    "count": 58,
    "stem": "foe",
    "term": "foes"
  },
  {
    "count": 58,
    "stem": "stanlei",
    "term": "stanley"
  },
  {
    "count": 58,
    "stem": "castro",
    "term": "castro"
  },
  {
    "count": 58,
    "stem": "steer",
    "term": "steer"
  },
  {
    "count": 58,
    "stem": "nasa",
    "term": "nasa"
  },
  {
    "count": 58,
    "stem": "envision",
    "term": "envisioned"
  },
  {
    "count": 58,
    "stem": "impli",
    "term": "implied"
  },
  {
    "count": 58,
    "stem": "elev",
    "term": "elevated"
  },
  {
    "count": 58,
    "stem": "exploit",
    "term": "exploit"
  },
  {
    "count": 58,
    "stem": "toler",
    "term": "tolerance"
  },
  {
    "count": 58,
    "stem": "grappl",
    "term": "grapple"
  },
  {
    "count": 58,
    "stem": "cave",
    "term": "caves"
  },
  {
    "count": 58,
    "stem": "anchor",
    "term": "anchor"
  },
  {
    "count": 58,
    "stem": "landler",
    "term": "landler"
  },
  {
    "count": 58,
    "stem": "wilson",
    "term": "wilson"
  },
  {
    "count": 58,
    "stem": "testifi",
    "term": "testified"
  },
  {
    "count": 58,
    "stem": "regain",
    "term": "regain"
  },
  {
    "count": 58,
    "stem": "moin",
    "term": "moines"
  },
  {
    "count": 58,
    "stem": "extract",
    "term": "extract"
  },
  {
    "count": 57,
    "stem": "lindsei",
    "term": "lindsey"
  },
  {
    "count": 57,
    "stem": "nebraska",
    "term": "nebraska"
  },
  {
    "count": 57,
    "stem": "repriev",
    "term": "reprieves"
  },
  {
    "count": 57,
    "stem": "commenc",
    "term": "commencement"
  },
  {
    "count": 57,
    "stem": "gene",
    "term": "gene"
  },
  {
    "count": 57,
    "stem": "ted",
    "term": "ted"
  },
  {
    "count": 57,
    "stem": "boast",
    "term": "boasted"
  },
  {
    "count": 57,
    "stem": "marketplac",
    "term": "marketplace"
  },
  {
    "count": 57,
    "stem": "faster",
    "term": "faster"
  },
  {
    "count": 57,
    "stem": "bunch",
    "term": "bunch"
  },
  {
    "count": 57,
    "stem": "biographi",
    "term": "biography"
  },
  {
    "count": 57,
    "stem": "resembl",
    "term": "resembles"
  },
  {
    "count": 57,
    "stem": "manipul",
    "term": "manipulation"
  },
  {
    "count": 57,
    "stem": "navig",
    "term": "navigate"
  },
  {
    "count": 57,
    "stem": "deepwat",
    "term": "deepwater"
  },
  {
    "count": 57,
    "stem": "disabl",
    "term": "disabled"
  },
  {
    "count": 56,
    "stem": "miller",
    "term": "miller"
  },
  {
    "count": 56,
    "stem": "legislatur",
    "term": "legislature"
  },
  {
    "count": 56,
    "stem": "henri",
    "term": "henry"
  },
  {
    "count": 56,
    "stem": "mainstream",
    "term": "mainstream"
  },
  {
    "count": 56,
    "stem": "guidelin",
    "term": "guidelines"
  },
  {
    "count": 56,
    "stem": "arctic",
    "term": "arctic"
  },
  {
    "count": 56,
    "stem": "babbitt",
    "term": "babbitt"
  },
  {
    "count": 56,
    "stem": "cellphon",
    "term": "cellphone"
  },
  {
    "count": 56,
    "stem": "fanni",
    "term": "fannie"
  },
  {
    "count": 56,
    "stem": "louisiana",
    "term": "louisiana"
  },
  {
    "count": 56,
    "stem": "specter",
    "term": "specter"
  },
  {
    "count": 56,
    "stem": "burton",
    "term": "burton"
  },
  {
    "count": 56,
    "stem": "ammunit",
    "term": "ammunition"
  },
  {
    "count": 56,
    "stem": "yucca",
    "term": "yucca"
  },
  {
    "count": 56,
    "stem": "holbrook",
    "term": "holbrooke"
  },
  {
    "count": 56,
    "stem": "rep",
    "term": "rep"
  },
  {
    "count": 56,
    "stem": "cain",
    "term": "cain"
  },
  {
    "count": 56,
    "stem": "flip",
    "term": "flip"
  },
  {
    "count": 56,
    "stem": "ratifi",
    "term": "ratify"
  },
  {
    "count": 56,
    "stem": "blueprint",
    "term": "blueprint"
  },
  {
    "count": 56,
    "stem": "manchin",
    "term": "manchin"
  },
  {
    "count": 56,
    "stem": "fossil",
    "term": "fossil"
  },
  {
    "count": 56,
    "stem": "dispatch",
    "term": "dispatched"
  },
  {
    "count": 56,
    "stem": "allud",
    "term": "alluding"
  },
  {
    "count": 56,
    "stem": "quinnipiac",
    "term": "quinnipiac"
  },
  {
    "count": 56,
    "stem": "jew",
    "term": "jews"
  },
  {
    "count": 55,
    "stem": "inspector",
    "term": "inspectors"
  },
  {
    "count": 55,
    "stem": "freddi",
    "term": "freddie"
  },
  {
    "count": 55,
    "stem": "repudi",
    "term": "repudiation"
  },
  {
    "count": 55,
    "stem": "patrick",
    "term": "patrick"
  },
  {
    "count": 55,
    "stem": "reckless",
    "term": "reckless"
  },
  {
    "count": 55,
    "stem": "hama",
    "term": "hamas"
  },
  {
    "count": 55,
    "stem": "petition",
    "term": "petition"
  },
  {
    "count": 55,
    "stem": "button",
    "term": "button"
  },
  {
    "count": 55,
    "stem": "valeri",
    "term": "valerie"
  },
  {
    "count": 55,
    "stem": "goolsbe",
    "term": "goolsbee"
  },
  {
    "count": 55,
    "stem": "beck",
    "term": "beck"
  },
  {
    "count": 55,
    "stem": "bipartisanship",
    "term": "bipartisanship"
  },
  {
    "count": 55,
    "stem": "satellit",
    "term": "satellite"
  },
  {
    "count": 55,
    "stem": "jacki",
    "term": "jackie"
  },
  {
    "count": 55,
    "stem": "interrupt",
    "term": "interrupted"
  },
  {
    "count": 55,
    "stem": "tariff",
    "term": "tariffs"
  },
  {
    "count": 55,
    "stem": "georgetown",
    "term": "georgetown"
  },
  {
    "count": 55,
    "stem": "poison",
    "term": "poison"
  },
  {
    "count": 55,
    "stem": "recipi",
    "term": "recipients"
  },
  {
    "count": 55,
    "stem": "prevail",
    "term": "prevail"
  },
  {
    "count": 55,
    "stem": "souza",
    "term": "souza"
  },
  {
    "count": 55,
    "stem": "compens",
    "term": "compensation"
  },
  {
    "count": 55,
    "stem": "upset",
    "term": "upset"
  },
  {
    "count": 54,
    "stem": "essai",
    "term": "essay"
  },
  {
    "count": 54,
    "stem": "modif",
    "term": "modifications"
  },
  {
    "count": 54,
    "stem": "dig",
    "term": "dig"
  },
  {
    "count": 54,
    "stem": "longstand",
    "term": "longstanding"
  },
  {
    "count": 54,
    "stem": "columnist",
    "term": "columnist"
  },
  {
    "count": 54,
    "stem": "convei",
    "term": "convey"
  },
  {
    "count": 54,
    "stem": "midwest",
    "term": "midwest"
  },
  {
    "count": 54,
    "stem": "wireless",
    "term": "wireless"
  },
  {
    "count": 54,
    "stem": "dick",
    "term": "dick"
  },
  {
    "count": 54,
    "stem": "gridlock",
    "term": "gridlock"
  },
  {
    "count": 54,
    "stem": "nixon",
    "term": "nixon"
  },
  {
    "count": 54,
    "stem": "refrain",
    "term": "refrain"
  },
  {
    "count": 54,
    "stem": "kyl",
    "term": "kyl"
  },
  {
    "count": 53,
    "stem": "earner",
    "term": "earners"
  },
  {
    "count": 53,
    "stem": "flank",
    "term": "flanked"
  },
  {
    "count": 53,
    "stem": "nutrition",
    "term": "nutrition"
  },
  {
    "count": 53,
    "stem": "poster",
    "term": "poster"
  },
  {
    "count": 53,
    "stem": "honolulu",
    "term": "honolulu"
  },
  {
    "count": 53,
    "stem": "hussein",
    "term": "hussein"
  },
  {
    "count": 53,
    "stem": "betrai",
    "term": "betrayed"
  },
  {
    "count": 53,
    "stem": "pend",
    "term": "pending"
  },
  {
    "count": 53,
    "stem": "repris",
    "term": "reprising"
  },
  {
    "count": 53,
    "stem": "quest",
    "term": "quest"
  },
  {
    "count": 53,
    "stem": "restraint",
    "term": "restraint"
  },
  {
    "count": 53,
    "stem": "dmitri",
    "term": "dmitri"
  },
  {
    "count": 53,
    "stem": "buck",
    "term": "buck"
  },
  {
    "count": 53,
    "stem": "backlash",
    "term": "backlash"
  },
  {
    "count": 53,
    "stem": "sour",
    "term": "sour"
  },
  {
    "count": 53,
    "stem": "partisanship",
    "term": "partisanship"
  },
  {
    "count": 53,
    "stem": "breakthrough",
    "term": "breakthrough"
  },
  {
    "count": 52,
    "stem": "distort",
    "term": "distorting"
  },
  {
    "count": 52,
    "stem": "woe",
    "term": "woes"
  },
  {
    "count": 52,
    "stem": "implor",
    "term": "implored"
  },
  {
    "count": 52,
    "stem": "crush",
    "term": "crushing"
  },
  {
    "count": 52,
    "stem": "stadium",
    "term": "stadium"
  },
  {
    "count": 52,
    "stem": "evangel",
    "term": "evangelical"
  },
  {
    "count": 52,
    "stem": "canadian",
    "term": "canadian"
  },
  {
    "count": 52,
    "stem": "preview",
    "term": "preview"
  },
  {
    "count": 52,
    "stem": "hassan",
    "term": "hassan"
  },
  {
    "count": 52,
    "stem": "proclaim",
    "term": "proclaimed"
  },
  {
    "count": 52,
    "stem": "euro",
    "term": "euro"
  },
  {
    "count": 52,
    "stem": "iren",
    "term": "irene"
  },
  {
    "count": 52,
    "stem": "smog",
    "term": "smog"
  },
  {
    "count": 52,
    "stem": "rai",
    "term": "ray"
  },
  {
    "count": 52,
    "stem": "midst",
    "term": "midst"
  },
  {
    "count": 51,
    "stem": "walter",
    "term": "walter"
  },
  {
    "count": 51,
    "stem": "furor",
    "term": "furor"
  },
  {
    "count": 51,
    "stem": "chant",
    "term": "chants"
  },
  {
    "count": 51,
    "stem": "elementari",
    "term": "elementary"
  },
  {
    "count": 51,
    "stem": "automak",
    "term": "automakers"
  },
  {
    "count": 51,
    "stem": "god",
    "term": "god"
  },
  {
    "count": 51,
    "stem": "woo",
    "term": "woo"
  },
  {
    "count": 51,
    "stem": "hurdl",
    "term": "hurdles"
  },
  {
    "count": 51,
    "stem": "mislead",
    "term": "misleading"
  },
  {
    "count": 51,
    "stem": "stern",
    "term": "stern"
  },
  {
    "count": 51,
    "stem": "rift",
    "term": "rift"
  },
  {
    "count": 51,
    "stem": "english",
    "term": "english"
  },
  {
    "count": 51,
    "stem": "sebeliu",
    "term": "sebelius"
  },
  {
    "count": 51,
    "stem": "subsequ",
    "term": "subsequent"
  },
  {
    "count": 51,
    "stem": "firefight",
    "term": "firefighters"
  },
  {
    "count": 51,
    "stem": "safeguard",
    "term": "safeguards"
  },
  {
    "count": 51,
    "stem": "relax",
    "term": "relaxed"
  },
  {
    "count": 51,
    "stem": "unwil",
    "term": "unwilling"
  },
  {
    "count": 51,
    "stem": "pete",
    "term": "pete"
  },
  {
    "count": 51,
    "stem": "memoir",
    "term": "memoir"
  },
  {
    "count": 51,
    "stem": "worsen",
    "term": "worsening"
  },
  {
    "count": 51,
    "stem": "aisl",
    "term": "aisle"
  },
  {
    "count": 50,
    "stem": "widen",
    "term": "widening"
  },
  {
    "count": 50,
    "stem": "swai",
    "term": "sway"
  },
  {
    "count": 50,
    "stem": "ireland",
    "term": "ireland"
  },
  {
    "count": 50,
    "stem": "menu",
    "term": "menu"
  },
  {
    "count": 50,
    "stem": "dioxid",
    "term": "dioxide"
  },
  {
    "count": 50,
    "stem": "quo",
    "term": "quo"
  },
  {
    "count": 50,
    "stem": "holland",
    "term": "hollande"
  },
  {
    "count": 50,
    "stem": "rollout",
    "term": "rollout"
  },
  {
    "count": 50,
    "stem": "pastor",
    "term": "pastor"
  },
  {
    "count": 50,
    "stem": "poland",
    "term": "poland"
  },
  {
    "count": 50,
    "stem": "franklin",
    "term": "franklin"
  },
  {
    "count": 50,
    "stem": "firearm",
    "term": "firearms"
  },
  {
    "count": 50,
    "stem": "lou",
    "term": "lou"
  },
  {
    "count": 50,
    "stem": "pulpit",
    "term": "pulpit"
  },
  {
    "count": 50,
    "stem": "barrier",
    "term": "barriers"
  },
  {
    "count": 50,
    "stem": "affluent",
    "term": "affluent"
  },
  {
    "count": 50,
    "stem": "lawrenc",
    "term": "lawrence"
  },
  {
    "count": 50,
    "stem": "nativ",
    "term": "native"
  },
  {
    "count": 50,
    "stem": "duncan",
    "term": "duncan"
  },
  {
    "count": 50,
    "stem": "asylum",
    "term": "asylum"
  },
  {
    "count": 50,
    "stem": "itali",
    "term": "italy"
  },
  {
    "count": 49,
    "stem": "judiciari",
    "term": "judiciary"
  },
  {
    "count": 49,
    "stem": "rational",
    "term": "rationale"
  },
  {
    "count": 49,
    "stem": "scenario",
    "term": "scenario"
  },
  {
    "count": 49,
    "stem": "weiner",
    "term": "weiner"
  },
  {
    "count": 49,
    "stem": "postur",
    "term": "posture"
  },
  {
    "count": 49,
    "stem": "ridicul",
    "term": "ridiculous"
  },
  {
    "count": 49,
    "stem": "stricter",
    "term": "stricter"
  },
  {
    "count": 49,
    "stem": "coincid",
    "term": "coincidence"
  },
  {
    "count": 49,
    "stem": "springsteen",
    "term": "springsteen"
  },
  {
    "count": 49,
    "stem": "globe",
    "term": "globe"
  },
  {
    "count": 49,
    "stem": "bump",
    "term": "bump"
  },
  {
    "count": 49,
    "stem": "mideast",
    "term": "mideast"
  },
  {
    "count": 49,
    "stem": "litig",
    "term": "litigation"
  },
  {
    "count": 49,
    "stem": "puerto",
    "term": "puerto"
  },
  {
    "count": 49,
    "stem": "powel",
    "term": "powell"
  },
  {
    "count": 49,
    "stem": "boom",
    "term": "boom"
  },
  {
    "count": 49,
    "stem": "embodi",
    "term": "embodied"
  },
  {
    "count": 49,
    "stem": "unleash",
    "term": "unleashed"
  },
  {
    "count": 49,
    "stem": "immelt",
    "term": "immelt"
  },
  {
    "count": 49,
    "stem": "substant",
    "term": "substantive"
  },
  {
    "count": 49,
    "stem": "vocal",
    "term": "vocal"
  },
  {
    "count": 49,
    "stem": "charli",
    "term": "charlie"
  },
  {
    "count": 49,
    "stem": "restructur",
    "term": "restructuring"
  },
  {
    "count": 49,
    "stem": "salut",
    "term": "salute"
  },
  {
    "count": 49,
    "stem": "nieto",
    "term": "nieto"
  },
  {
    "count": 49,
    "stem": "wolf",
    "term": "wolf"
  },
  {
    "count": 49,
    "stem": "cynic",
    "term": "cynical"
  },
  {
    "count": 48,
    "stem": "discretionari",
    "term": "discretionary"
  },
  {
    "count": 48,
    "stem": "reilli",
    "term": "reilly"
  },
  {
    "count": 48,
    "stem": "nelson",
    "term": "nelson"
  },
  {
    "count": 48,
    "stem": "conting",
    "term": "contingent"
  },
  {
    "count": 48,
    "stem": "rocket",
    "term": "rocket"
  },
  {
    "count": 48,
    "stem": "fare",
    "term": "fare"
  },
  {
    "count": 48,
    "stem": "rumor",
    "term": "rumors"
  },
  {
    "count": 48,
    "stem": "teenag",
    "term": "teenager"
  },
  {
    "count": 48,
    "stem": "upheav",
    "term": "upheaval"
  },
  {
    "count": 48,
    "stem": "maraniss",
    "term": "maraniss"
  },
  {
    "count": 48,
    "stem": "accommod",
    "term": "accommodate"
  },
  {
    "count": 48,
    "stem": "trigger",
    "term": "trigger"
  },
  {
    "count": 48,
    "stem": "entrepreneur",
    "term": "entrepreneurs"
  },
  {
    "count": 48,
    "stem": "alan",
    "term": "alan"
  },
  {
    "count": 48,
    "stem": "costa",
    "term": "costa"
  },
  {
    "count": 48,
    "stem": "punch",
    "term": "punch"
  },
  {
    "count": 48,
    "stem": "invasion",
    "term": "invasion"
  },
  {
    "count": 48,
    "stem": "excerpt",
    "term": "excerpts"
  },
  {
    "count": 48,
    "stem": "weren",
    "term": "weren"
  },
  {
    "count": 48,
    "stem": "whistl",
    "term": "whistle"
  },
  {
    "count": 48,
    "stem": "bankrupt",
    "term": "bankrupt"
  },
  {
    "count": 47,
    "stem": "reelect",
    "term": "reelection"
  },
  {
    "count": 47,
    "stem": "stoke",
    "term": "stoked"
  },
  {
    "count": 47,
    "stem": "brink",
    "term": "brink"
  },
  {
    "count": 47,
    "stem": "elderli",
    "term": "elderly"
  },
  {
    "count": 47,
    "stem": "threshold",
    "term": "threshold"
  },
  {
    "count": 47,
    "stem": "van",
    "term": "van"
  },
  {
    "count": 47,
    "stem": "arena",
    "term": "arena"
  },
  {
    "count": 47,
    "stem": "labolt",
    "term": "labolt"
  },
  {
    "count": 47,
    "stem": "thwart",
    "term": "thwart"
  },
  {
    "count": 47,
    "stem": "freshman",
    "term": "freshman"
  },
  {
    "count": 47,
    "stem": "loyal",
    "term": "loyal"
  },
  {
    "count": 47,
    "stem": "copenhagen",
    "term": "copenhagen"
  },
  {
    "count": 47,
    "stem": "bilater",
    "term": "bilateral"
  },
  {
    "count": 47,
    "stem": "chao",
    "term": "chaos"
  },
  {
    "count": 47,
    "stem": "gallon",
    "term": "gallon"
  },
  {
    "count": 47,
    "stem": "mac",
    "term": "mac"
  },
  {
    "count": 47,
    "stem": "deflect",
    "term": "deflect"
  },
  {
    "count": 47,
    "stem": "helen",
    "term": "helene"
  },
  {
    "count": 47,
    "stem": "gambl",
    "term": "gamble"
  },
  {
    "count": 47,
    "stem": "reconsid",
    "term": "reconsider"
  },
  {
    "count": 47,
    "stem": "bless",
    "term": "blessing"
  },
  {
    "count": 47,
    "stem": "setback",
    "term": "setback"
  },
  {
    "count": 47,
    "stem": "riski",
    "term": "risky"
  },
  {
    "count": 47,
    "stem": "interim",
    "term": "interim"
  },
  {
    "count": 46,
    "stem": "rewrit",
    "term": "rewrite"
  },
  {
    "count": 46,
    "stem": "timelin",
    "term": "timeline"
  },
  {
    "count": 46,
    "stem": "safer",
    "term": "safer"
  },
  {
    "count": 46,
    "stem": "acr",
    "term": "acres"
  },
  {
    "count": 46,
    "stem": "crude",
    "term": "crude"
  },
  {
    "count": 46,
    "stem": "chu",
    "term": "chu"
  },
  {
    "count": 46,
    "stem": "doom",
    "term": "doomed"
  },
  {
    "count": 46,
    "stem": "winfrei",
    "term": "winfrey"
  },
  {
    "count": 46,
    "stem": "damascu",
    "term": "damascus"
  },
  {
    "count": 46,
    "stem": "kelli",
    "term": "kelly"
  },
  {
    "count": 46,
    "stem": "rattner",
    "term": "rattner"
  },
  {
    "count": 46,
    "stem": "businessman",
    "term": "businessman"
  },
  {
    "count": 46,
    "stem": "chide",
    "term": "chided"
  },
  {
    "count": 46,
    "stem": "airlin",
    "term": "airlines"
  },
  {
    "count": 46,
    "stem": "ratif",
    "term": "ratification"
  },
  {
    "count": 46,
    "stem": "chase",
    "term": "chase"
  },
  {
    "count": 46,
    "stem": "salazar",
    "term": "salazar"
  },
  {
    "count": 46,
    "stem": "pit",
    "term": "pit"
  },
  {
    "count": 46,
    "stem": "casualti",
    "term": "casualties"
  },
  {
    "count": 46,
    "stem": "uninsur",
    "term": "uninsured"
  },
  {
    "count": 46,
    "stem": "heal",
    "term": "heal"
  },
  {
    "count": 46,
    "stem": "scrap",
    "term": "scrap"
  },
  {
    "count": 46,
    "stem": "geneva",
    "term": "geneva"
  },
  {
    "count": 46,
    "stem": "blogrunn",
    "term": "blogrunner"
  },
  {
    "count": 46,
    "stem": "markei",
    "term": "markey"
  },
  {
    "count": 46,
    "stem": "compli",
    "term": "comply"
  },
  {
    "count": 46,
    "stem": "ongo",
    "term": "ongoing"
  },
  {
    "count": 46,
    "stem": "exhaust",
    "term": "exhausted"
  },
  {
    "count": 46,
    "stem": "bail",
    "term": "bail"
  },
  {
    "count": 46,
    "stem": "janet",
    "term": "janet"
  },
  {
    "count": 46,
    "stem": "commentari",
    "term": "commentary"
  },
  {
    "count": 46,
    "stem": "linger",
    "term": "lingering"
  },
  {
    "count": 46,
    "stem": "hike",
    "term": "hikes"
  },
  {
    "count": 46,
    "stem": "covert",
    "term": "covert"
  },
  {
    "count": 45,
    "stem": "dobb",
    "term": "dobbs"
  },
  {
    "count": 45,
    "stem": "tobacco",
    "term": "tobacco"
  },
  {
    "count": 45,
    "stem": "balk",
    "term": "balk"
  },
  {
    "count": 45,
    "stem": "oprah",
    "term": "oprah"
  },
  {
    "count": 45,
    "stem": "princ",
    "term": "prince"
  },
  {
    "count": 45,
    "stem": "curtail",
    "term": "curtail"
  },
  {
    "count": 45,
    "stem": "cyberattack",
    "term": "cyberattacks"
  },
  {
    "count": 45,
    "stem": "mullen",
    "term": "mullen"
  },
  {
    "count": 45,
    "stem": "duel",
    "term": "dueling"
  },
  {
    "count": 45,
    "stem": "risen",
    "term": "risen"
  },
  {
    "count": 45,
    "stem": "contradict",
    "term": "contradict"
  },
  {
    "count": 45,
    "stem": "stun",
    "term": "stunning"
  },
  {
    "count": 45,
    "stem": "tar",
    "term": "tar"
  },
  {
    "count": 45,
    "stem": "plausibl",
    "term": "plausible"
  },
  {
    "count": 45,
    "stem": "gail",
    "term": "gail"
  },
  {
    "count": 45,
    "stem": "discourag",
    "term": "discouraged"
  },
  {
    "count": 45,
    "stem": "laps",
    "term": "lapses"
  },
  {
    "count": 44,
    "stem": "liabil",
    "term": "liability"
  },
  {
    "count": 44,
    "stem": "ken",
    "term": "ken"
  },
  {
    "count": 44,
    "stem": "legitimaci",
    "term": "legitimacy"
  },
  {
    "count": 44,
    "stem": "batteri",
    "term": "battery"
  },
  {
    "count": 44,
    "stem": "chat",
    "term": "chat"
  },
  {
    "count": 44,
    "stem": "phoenix",
    "term": "phoenix"
  },
  {
    "count": 44,
    "stem": "wrestl",
    "term": "wrestling"
  },
  {
    "count": 44,
    "stem": "derid",
    "term": "derided"
  },
  {
    "count": 44,
    "stem": "christoph",
    "term": "christopher"
  },
  {
    "count": 44,
    "stem": "eisenhow",
    "term": "eisenhower"
  },
  {
    "count": 44,
    "stem": "refin",
    "term": "refinance"
  },
  {
    "count": 44,
    "stem": "barbour",
    "term": "barbour"
  },
  {
    "count": 44,
    "stem": "statehood",
    "term": "statehood"
  },
  {
    "count": 44,
    "stem": "denni",
    "term": "dennis"
  },
  {
    "count": 44,
    "stem": "tayyip",
    "term": "tayyip"
  },
  {
    "count": 44,
    "stem": "commemor",
    "term": "commemorate"
  },
  {
    "count": 44,
    "stem": "iii",
    "term": "iii"
  },
  {
    "count": 44,
    "stem": "dean",
    "term": "dean"
  },
  {
    "count": 44,
    "stem": "modifi",
    "term": "modified"
  },
  {
    "count": 44,
    "stem": "julia",
    "term": "julia"
  },
  {
    "count": 44,
    "stem": "richmond",
    "term": "richmond"
  },
  {
    "count": 44,
    "stem": "deterior",
    "term": "deteriorating"
  },
  {
    "count": 44,
    "stem": "explos",
    "term": "explosives"
  },
  {
    "count": 44,
    "stem": "microphon",
    "term": "microphone"
  },
  {
    "count": 44,
    "stem": "frankli",
    "term": "frankly"
  },
  {
    "count": 44,
    "stem": "rape",
    "term": "rape"
  },
  {
    "count": 44,
    "stem": "unnecessari",
    "term": "unnecessary"
  },
  {
    "count": 44,
    "stem": "lag",
    "term": "lagging"
  },
  {
    "count": 44,
    "stem": "gender",
    "term": "gender"
  },
  {
    "count": 44,
    "stem": "remak",
    "term": "remake"
  },
  {
    "count": 44,
    "stem": "grim",
    "term": "grim"
  },
  {
    "count": 43,
    "stem": "turner",
    "term": "turner"
  },
  {
    "count": 43,
    "stem": "nudg",
    "term": "nudge"
  },
  {
    "count": 43,
    "stem": "hawk",
    "term": "hawks"
  },
  {
    "count": 43,
    "stem": "slate",
    "term": "slate"
  },
  {
    "count": 43,
    "stem": "simultan",
    "term": "simultaneously"
  },
  {
    "count": 43,
    "stem": "fleet",
    "term": "fleet"
  },
  {
    "count": 43,
    "stem": "matt",
    "term": "matt"
  },
  {
    "count": 43,
    "stem": "appeas",
    "term": "appease"
  },
  {
    "count": 43,
    "stem": "orlando",
    "term": "orlando"
  },
  {
    "count": 43,
    "stem": "schultz",
    "term": "schultz"
  },
  {
    "count": 43,
    "stem": "discours",
    "term": "discourse"
  },
  {
    "count": 43,
    "stem": "bloodi",
    "term": "bloody"
  },
  {
    "count": 43,
    "stem": "takeov",
    "term": "takeover"
  },
  {
    "count": 43,
    "stem": "inflict",
    "term": "inflicted"
  },
  {
    "count": 43,
    "stem": "brian",
    "term": "brian"
  },
  {
    "count": 43,
    "stem": "wade",
    "term": "wade"
  },
  {
    "count": 43,
    "stem": "credenti",
    "term": "credentials"
  },
  {
    "count": 43,
    "stem": "script",
    "term": "script"
  },
  {
    "count": 43,
    "stem": "formid",
    "term": "formidable"
  },
  {
    "count": 43,
    "stem": "ford",
    "term": "ford"
  },
  {
    "count": 43,
    "stem": "cultiv",
    "term": "cultivated"
  },
  {
    "count": 43,
    "stem": "sunni",
    "term": "sunni"
  },
  {
    "count": 43,
    "stem": "lawn",
    "term": "lawn"
  },
  {
    "count": 43,
    "stem": "greec",
    "term": "greece"
  },
  {
    "count": 43,
    "stem": "blitz",
    "term": "blitz"
  },
  {
    "count": 43,
    "stem": "pat",
    "term": "pat"
  },
  {
    "count": 43,
    "stem": "conciliatori",
    "term": "conciliatory"
  },
  {
    "count": 43,
    "stem": "resent",
    "term": "resentment"
  },
  {
    "count": 43,
    "stem": "soviet",
    "term": "soviet"
  },
  {
    "count": 43,
    "stem": "venezuela",
    "term": "venezuela"
  },
  {
    "count": 43,
    "stem": "visa",
    "term": "visas"
  },
  {
    "count": 43,
    "stem": "parenthood",
    "term": "parenthood"
  },
  {
    "count": 43,
    "stem": "reconcili",
    "term": "reconciliation"
  },
  {
    "count": 43,
    "stem": "moon",
    "term": "moon"
  },
  {
    "count": 43,
    "stem": "atlanta",
    "term": "atlanta"
  },
  {
    "count": 43,
    "stem": "gari",
    "term": "gary"
  },
  {
    "count": 43,
    "stem": "woodward",
    "term": "woodward"
  },
  {
    "count": 42,
    "stem": "saleh",
    "term": "saleh"
  },
  {
    "count": 42,
    "stem": "dakota",
    "term": "dakota"
  },
  {
    "count": 42,
    "stem": "explosion",
    "term": "explosion"
  },
  {
    "count": 42,
    "stem": "bite",
    "term": "bite"
  },
  {
    "count": 42,
    "stem": "crippl",
    "term": "crippling"
  },
  {
    "count": 42,
    "stem": "undo",
    "term": "undo"
  },
  {
    "count": 42,
    "stem": "leno",
    "term": "leno"
  },
  {
    "count": 42,
    "stem": "bracket",
    "term": "bracket"
  },
  {
    "count": 42,
    "stem": "belt",
    "term": "belt"
  },
  {
    "count": 42,
    "stem": "slaughter",
    "term": "slaughter"
  },
  {
    "count": 42,
    "stem": "broaden",
    "term": "broaden"
  },
  {
    "count": 42,
    "stem": "jeremiah",
    "term": "jeremiah"
  },
  {
    "count": 42,
    "stem": "kagan",
    "term": "kagan"
  },
  {
    "count": 42,
    "stem": "usher",
    "term": "ushered"
  },
  {
    "count": 42,
    "stem": "revolt",
    "term": "revolt"
  },
  {
    "count": 42,
    "stem": "overreach",
    "term": "overreach"
  },
  {
    "count": 42,
    "stem": "mccarthi",
    "term": "mccarthy"
  },
  {
    "count": 42,
    "stem": "herald",
    "term": "herald"
  },
  {
    "count": 42,
    "stem": "unfavor",
    "term": "unfavorable"
  },
  {
    "count": 42,
    "stem": "outspoken",
    "term": "outspoken"
  },
  {
    "count": 42,
    "stem": "detain",
    "term": "detained"
  },
  {
    "count": 42,
    "stem": "tribal",
    "term": "tribal"
  },
  {
    "count": 42,
    "stem": "revamp",
    "term": "revamp"
  },
  {
    "count": 42,
    "stem": "embattl",
    "term": "embattled"
  },
  {
    "count": 42,
    "stem": "hometown",
    "term": "hometown"
  },
  {
    "count": 42,
    "stem": "tighter",
    "term": "tighter"
  },
  {
    "count": 42,
    "stem": "laud",
    "term": "lauded"
  },
  {
    "count": 42,
    "stem": "showcas",
    "term": "showcase"
  },
  {
    "count": 42,
    "stem": "rica",
    "term": "rica"
  },
  {
    "count": 42,
    "stem": "imper",
    "term": "imperative"
  },
  {
    "count": 42,
    "stem": "discov",
    "term": "discovered"
  },
  {
    "count": 42,
    "stem": "tilt",
    "term": "tilt"
  },
  {
    "count": 42,
    "stem": "ministri",
    "term": "ministry"
  },
  {
    "count": 42,
    "stem": "obstruct",
    "term": "obstruction"
  },
  {
    "count": 42,
    "stem": "steep",
    "term": "steep"
  },
  {
    "count": 42,
    "stem": "thanksgiv",
    "term": "thanksgiving"
  },
  {
    "count": 42,
    "stem": "haul",
    "term": "haul"
  },
  {
    "count": 42,
    "stem": "disdain",
    "term": "disdain"
  },
  {
    "count": 41,
    "stem": "racist",
    "term": "racist"
  },
  {
    "count": 41,
    "stem": "withhold",
    "term": "withhold"
  },
  {
    "count": 41,
    "stem": "commando",
    "term": "commandos"
  },
  {
    "count": 41,
    "stem": "loui",
    "term": "louis"
  },
  {
    "count": 41,
    "stem": "cloonei",
    "term": "clooney"
  },
  {
    "count": 41,
    "stem": "recep",
    "term": "recep"
  },
  {
    "count": 41,
    "stem": "carrier",
    "term": "carrier"
  },
  {
    "count": 41,
    "stem": "allegi",
    "term": "allegiance"
  },
  {
    "count": 41,
    "stem": "tune",
    "term": "tune"
  },
  {
    "count": 41,
    "stem": "deter",
    "term": "deter"
  },
  {
    "count": 41,
    "stem": "ditch",
    "term": "ditch"
  },
  {
    "count": 41,
    "stem": "brewer",
    "term": "brewer"
  },
  {
    "count": 41,
    "stem": "kamal",
    "term": "kamal"
  },
  {
    "count": 41,
    "stem": "turf",
    "term": "turf"
  },
  {
    "count": 41,
    "stem": "trumpet",
    "term": "trumpeted"
  },
  {
    "count": 41,
    "stem": "goldman",
    "term": "goldman"
  },
  {
    "count": 41,
    "stem": "roman",
    "term": "roman"
  },
  {
    "count": 41,
    "stem": "cede",
    "term": "cede"
  },
  {
    "count": 41,
    "stem": "straw",
    "term": "straw"
  },
  {
    "count": 41,
    "stem": "kevin",
    "term": "kevin"
  },
  {
    "count": 41,
    "stem": "derail",
    "term": "derail"
  },
  {
    "count": 41,
    "stem": "ramp",
    "term": "ramp"
  },
  {
    "count": 41,
    "stem": "nuri",
    "term": "nuri"
  },
  {
    "count": 41,
    "stem": "spin",
    "term": "spin"
  },
  {
    "count": 41,
    "stem": "rasmussen",
    "term": "rasmussen"
  },
  {
    "count": 41,
    "stem": "meantim",
    "term": "meantime"
  },
  {
    "count": 41,
    "stem": "prematur",
    "term": "premature"
  },
  {
    "count": 41,
    "stem": "cambodia",
    "term": "cambodia"
  },
  {
    "count": 41,
    "stem": "jason",
    "term": "jason"
  },
  {
    "count": 41,
    "stem": "spar",
    "term": "spar"
  },
  {
    "count": 41,
    "stem": "peak",
    "term": "peak"
  },
  {
    "count": 41,
    "stem": "gabriel",
    "term": "gabrielle"
  },
  {
    "count": 41,
    "stem": "statut",
    "term": "statute"
  },
  {
    "count": 41,
    "stem": "consul",
    "term": "consulate"
  },
  {
    "count": 41,
    "stem": "catastroph",
    "term": "catastrophe"
  },
  {
    "count": 41,
    "stem": "relentless",
    "term": "relentless"
  },
  {
    "count": 41,
    "stem": "orlean",
    "term": "orleans"
  },
  {
    "count": 41,
    "stem": "volatil",
    "term": "volatile"
  },
  {
    "count": 40,
    "stem": "deploy",
    "term": "deployment"
  },
  {
    "count": 40,
    "stem": "revisit",
    "term": "revisited"
  },
  {
    "count": 40,
    "stem": "abraham",
    "term": "abraham"
  },
  {
    "count": 40,
    "stem": "summon",
    "term": "summoned"
  },
  {
    "count": 40,
    "stem": "obscur",
    "term": "obscure"
  },
  {
    "count": 40,
    "stem": "mae",
    "term": "mae"
  },
  {
    "count": 40,
    "stem": "hawaiian",
    "term": "hawaiian"
  },
  {
    "count": 40,
    "stem": "milwauke",
    "term": "milwaukee"
  },
  {
    "count": 40,
    "stem": "pill",
    "term": "pill"
  },
  {
    "count": 40,
    "stem": "constrain",
    "term": "constrained"
  },
  {
    "count": 40,
    "stem": "disastr",
    "term": "disastrous"
  },
  {
    "count": 40,
    "stem": "exclud",
    "term": "excluding"
  },
  {
    "count": 40,
    "stem": "embolden",
    "term": "emboldened"
  },
  {
    "count": 40,
    "stem": "likelihood",
    "term": "likelihood"
  },
  {
    "count": 40,
    "stem": "stockpil",
    "term": "stockpiles"
  },
  {
    "count": 40,
    "stem": "nurs",
    "term": "nursing"
  },
  {
    "count": 40,
    "stem": "tennesse",
    "term": "tennessee"
  },
  {
    "count": 40,
    "stem": "tripoli",
    "term": "tripoli"
  },
  {
    "count": 40,
    "stem": "yorker",
    "term": "yorker"
  },
  {
    "count": 40,
    "stem": "sean",
    "term": "sean"
  },
  {
    "count": 40,
    "stem": "mormon",
    "term": "mormon"
  },
  {
    "count": 40,
    "stem": "islamabad",
    "term": "islamabad"
  },
  {
    "count": 40,
    "stem": "healthcar",
    "term": "healthcare"
  },
  {
    "count": 40,
    "stem": "athlet",
    "term": "athletes"
  },
  {
    "count": 40,
    "stem": "yellen",
    "term": "yellen"
  },
  {
    "count": 40,
    "stem": "swap",
    "term": "swaps"
  },
  {
    "count": 40,
    "stem": "decri",
    "term": "decried"
  },
  {
    "count": 40,
    "stem": "temper",
    "term": "tempered"
  },
  {
    "count": 40,
    "stem": "shellack",
    "term": "shellacking"
  },
  {
    "count": 40,
    "stem": "somalia",
    "term": "somalia"
  },
  {
    "count": 40,
    "stem": "zeleni",
    "term": "zeleny"
  },
  {
    "count": 40,
    "stem": "booker",
    "term": "booker"
  },
  {
    "count": 40,
    "stem": "everywher",
    "term": "everywhere"
  },
  {
    "count": 40,
    "stem": "cohen",
    "term": "cohen"
  },
  {
    "count": 40,
    "stem": "wider",
    "term": "wider"
  },
  {
    "count": 40,
    "stem": "jab",
    "term": "jab"
  },
  {
    "count": 40,
    "stem": "pronounc",
    "term": "pronounced"
  },
  {
    "count": 40,
    "stem": "worldwid",
    "term": "worldwide"
  },
  {
    "count": 40,
    "stem": "arguabl",
    "term": "arguably"
  },
  {
    "count": 40,
    "stem": "lectur",
    "term": "lecture"
  },
  {
    "count": 40,
    "stem": "nuanc",
    "term": "nuanced"
  },
  {
    "count": 40,
    "stem": "expedit",
    "term": "expedited"
  },
  {
    "count": 40,
    "stem": "polish",
    "term": "polish"
  },
  {
    "count": 39,
    "stem": "overnight",
    "term": "overnight"
  },
  {
    "count": 39,
    "stem": "keynot",
    "term": "keynote"
  },
  {
    "count": 39,
    "stem": "spark",
    "term": "sparked"
  },
  {
    "count": 39,
    "stem": "tornado",
    "term": "tornado"
  },
  {
    "count": 39,
    "stem": "upheld",
    "term": "upheld"
  },
  {
    "count": 39,
    "stem": "interact",
    "term": "interactions"
  },
  {
    "count": 39,
    "stem": "swear",
    "term": "swearing"
  },
  {
    "count": 39,
    "stem": "adelson",
    "term": "adelson"
  },
  {
    "count": 39,
    "stem": "lash",
    "term": "lashed"
  },
  {
    "count": 39,
    "stem": "buyer",
    "term": "buyers"
  },
  {
    "count": 39,
    "stem": "chen",
    "term": "chen"
  },
  {
    "count": 39,
    "stem": "undocu",
    "term": "undocumented"
  },
  {
    "count": 39,
    "stem": "trayvon",
    "term": "trayvon"
  },
  {
    "count": 39,
    "stem": "taylor",
    "term": "taylor"
  },
  {
    "count": 39,
    "stem": "hitler",
    "term": "hitler"
  },
  {
    "count": 39,
    "stem": "hook",
    "term": "hook"
  },
  {
    "count": 39,
    "stem": "peninsula",
    "term": "peninsula"
  },
  {
    "count": 39,
    "stem": "weprin",
    "term": "weprin"
  },
  {
    "count": 39,
    "stem": "oregon",
    "term": "oregon"
  },
  {
    "count": 39,
    "stem": "imbal",
    "term": "imbalances"
  },
  {
    "count": 39,
    "stem": "monetari",
    "term": "monetary"
  },
  {
    "count": 39,
    "stem": "banner",
    "term": "banner"
  },
  {
    "count": 39,
    "stem": "anwar",
    "term": "anwar"
  },
  {
    "count": 39,
    "stem": "float",
    "term": "floated"
  },
  {
    "count": 39,
    "stem": "condol",
    "term": "condolences"
  },
  {
    "count": 39,
    "stem": "blower",
    "term": "blowers"
  },
  {
    "count": 39,
    "stem": "rob",
    "term": "rob"
  },
  {
    "count": 39,
    "stem": "drastic",
    "term": "drastically"
  },
  {
    "count": 39,
    "stem": "thrill",
    "term": "thrilled"
  },
  {
    "count": 39,
    "stem": "rand",
    "term": "rand"
  },
  {
    "count": 39,
    "stem": "collar",
    "term": "collar"
  },
  {
    "count": 38,
    "stem": "adm",
    "term": "adm"
  },
  {
    "count": 38,
    "stem": "dismal",
    "term": "dismal"
  },
  {
    "count": 38,
    "stem": "buri",
    "term": "buried"
  },
  {
    "count": 38,
    "stem": "stymi",
    "term": "stymied"
  },
  {
    "count": 38,
    "stem": "pretend",
    "term": "pretending"
  },
  {
    "count": 38,
    "stem": "russel",
    "term": "russell"
  },
  {
    "count": 38,
    "stem": "dempsei",
    "term": "dempsey"
  },
  {
    "count": 38,
    "stem": "swipe",
    "term": "swipe"
  },
  {
    "count": 38,
    "stem": "rethink",
    "term": "rethink"
  },
  {
    "count": 38,
    "stem": "creator",
    "term": "creator"
  },
  {
    "count": 38,
    "stem": "evolut",
    "term": "evolution"
  },
  {
    "count": 38,
    "stem": "elena",
    "term": "elena"
  },
  {
    "count": 38,
    "stem": "saul",
    "term": "saul"
  },
  {
    "count": 38,
    "stem": "acut",
    "term": "acute"
  },
  {
    "count": 38,
    "stem": "ouster",
    "term": "ouster"
  },
  {
    "count": 38,
    "stem": "pari",
    "term": "paris"
  },
  {
    "count": 38,
    "stem": "toppl",
    "term": "topple"
  },
  {
    "count": 38,
    "stem": "voucher",
    "term": "voucher"
  },
  {
    "count": 38,
    "stem": "upcom",
    "term": "upcoming"
  },
  {
    "count": 38,
    "stem": "zardari",
    "term": "zardari"
  },
  {
    "count": 38,
    "stem": "jill",
    "term": "jill"
  },
  {
    "count": 38,
    "stem": "ravag",
    "term": "ravaged"
  },
  {
    "count": 37,
    "stem": "elder",
    "term": "elder"
  },
  {
    "count": 37,
    "stem": "sticker",
    "term": "sticker"
  },
  {
    "count": 37,
    "stem": "twist",
    "term": "twist"
  },
  {
    "count": 37,
    "stem": "pop",
    "term": "pop"
  },
  {
    "count": 37,
    "stem": "stagnat",
    "term": "stagnation"
  },
  {
    "count": 37,
    "stem": "justif",
    "term": "justification"
  },
  {
    "count": 37,
    "stem": "deadlock",
    "term": "deadlock"
  },
  {
    "count": 37,
    "stem": "battlefield",
    "term": "battlefield"
  },
  {
    "count": 37,
    "stem": "flurri",
    "term": "flurry"
  },
  {
    "count": 37,
    "stem": "matthew",
    "term": "matthew"
  },
  {
    "count": 37,
    "stem": "glimps",
    "term": "glimpse"
  },
  {
    "count": 37,
    "stem": "murdoch",
    "term": "murdoch"
  },
  {
    "count": 37,
    "stem": "divert",
    "term": "divert"
  },
  {
    "count": 37,
    "stem": "restrain",
    "term": "restrained"
  },
  {
    "count": 37,
    "stem": "overshadow",
    "term": "overshadowed"
  },
  {
    "count": 37,
    "stem": "restart",
    "term": "restart"
  },
  {
    "count": 37,
    "stem": "tricki",
    "term": "tricky"
  },
  {
    "count": 37,
    "stem": "baghdad",
    "term": "baghdad"
  },
  {
    "count": 37,
    "stem": "commend",
    "term": "commend"
  },
  {
    "count": 37,
    "stem": "culmin",
    "term": "culmination"
  },
  {
    "count": 37,
    "stem": "dysfunct",
    "term": "dysfunctional"
  },
  {
    "count": 37,
    "stem": "rebuf",
    "term": "rebuffed"
  },
  {
    "count": 37,
    "stem": "devis",
    "term": "devise"
  },
  {
    "count": 37,
    "stem": "bruis",
    "term": "bruising"
  },
  {
    "count": 37,
    "stem": "verdict",
    "term": "verdict"
  },
  {
    "count": 37,
    "stem": "orient",
    "term": "orientation"
  },
  {
    "count": 37,
    "stem": "hunger",
    "term": "hunger"
  },
  {
    "count": 37,
    "stem": "fraught",
    "term": "fraught"
  },
  {
    "count": 37,
    "stem": "slap",
    "term": "slap"
  },
  {
    "count": 37,
    "stem": "miner",
    "term": "miners"
  },
  {
    "count": 37,
    "stem": "recaptur",
    "term": "recapture"
  },
  {
    "count": 37,
    "stem": "notifi",
    "term": "notified"
  },
  {
    "count": 37,
    "stem": "coup",
    "term": "coup"
  },
  {
    "count": 37,
    "stem": "kirk",
    "term": "kirk"
  },
  {
    "count": 37,
    "stem": "certifi",
    "term": "certified"
  },
  {
    "count": 37,
    "stem": "marco",
    "term": "marco"
  },
  {
    "count": 37,
    "stem": "wasserman",
    "term": "wasserman"
  },
  {
    "count": 37,
    "stem": "toughest",
    "term": "toughest"
  },
  {
    "count": 37,
    "stem": "barrag",
    "term": "barrage"
  },
  {
    "count": 37,
    "stem": "bloc",
    "term": "bloc"
  },
  {
    "count": 37,
    "stem": "contempl",
    "term": "contemplating"
  },
  {
    "count": 37,
    "stem": "montana",
    "term": "montana"
  },
  {
    "count": 37,
    "stem": "thread",
    "term": "thread"
  },
  {
    "count": 36,
    "stem": "descend",
    "term": "descended"
  },
  {
    "count": 36,
    "stem": "rocki",
    "term": "rocky"
  },
  {
    "count": 36,
    "stem": "upgrad",
    "term": "upgrade"
  },
  {
    "count": 36,
    "stem": "halfwai",
    "term": "halfway"
  },
  {
    "count": 36,
    "stem": "irrit",
    "term": "irritated"
  },
  {
    "count": 36,
    "stem": "turkish",
    "term": "turkish"
  },
  {
    "count": 36,
    "stem": "harlem",
    "term": "harlem"
  },
  {
    "count": 36,
    "stem": "sam",
    "term": "sam"
  },
  {
    "count": 36,
    "stem": "lyndon",
    "term": "lyndon"
  },
  {
    "count": 36,
    "stem": "clue",
    "term": "clues"
  },
  {
    "count": 36,
    "stem": "spous",
    "term": "spouses"
  },
  {
    "count": 36,
    "stem": "motorcad",
    "term": "motorcade"
  },
  {
    "count": 36,
    "stem": "palac",
    "term": "palace"
  },
  {
    "count": 36,
    "stem": "beyonc",
    "term": "beyonc"
  },
  {
    "count": 36,
    "stem": "uncomfort",
    "term": "uncomfortable"
  },
  {
    "count": 36,
    "stem": "detect",
    "term": "detection"
  },
  {
    "count": 36,
    "stem": "clearer",
    "term": "clearer"
  },
  {
    "count": 36,
    "stem": "tide",
    "term": "tide"
  },
  {
    "count": 36,
    "stem": "communist",
    "term": "communist"
  },
  {
    "count": 36,
    "stem": "southeast",
    "term": "southeast"
  },
  {
    "count": 36,
    "stem": "cup",
    "term": "cup"
  },
  {
    "count": 36,
    "stem": "soften",
    "term": "soften"
  },
  {
    "count": 36,
    "stem": "pension",
    "term": "pension"
  },
  {
    "count": 36,
    "stem": "outlet",
    "term": "outlets"
  },
  {
    "count": 36,
    "stem": "broadband",
    "term": "broadband"
  },
  {
    "count": 36,
    "stem": "mueller",
    "term": "mueller"
  },
  {
    "count": 36,
    "stem": "chip",
    "term": "chip"
  },
  {
    "count": 36,
    "stem": "rickett",
    "term": "ricketts"
  },
  {
    "count": 36,
    "stem": "tank",
    "term": "tank"
  },
  {
    "count": 36,
    "stem": "tran",
    "term": "trans"
  },
  {
    "count": 36,
    "stem": "comeback",
    "term": "comeback"
  },
  {
    "count": 36,
    "stem": "schumer",
    "term": "schumer"
  },
  {
    "count": 36,
    "stem": "anthoni",
    "term": "anthony"
  },
  {
    "count": 36,
    "stem": "grasp",
    "term": "grasp"
  },
  {
    "count": 36,
    "stem": "adher",
    "term": "adhere"
  },
  {
    "count": 36,
    "stem": "dire",
    "term": "dire"
  },
  {
    "count": 36,
    "stem": "kong",
    "term": "kong"
  },
  {
    "count": 36,
    "stem": "infuri",
    "term": "infuriated"
  },
  {
    "count": 36,
    "stem": "barbara",
    "term": "barbara"
  },
  {
    "count": 36,
    "stem": "tunisia",
    "term": "tunisia"
  },
  {
    "count": 36,
    "stem": "inject",
    "term": "injected"
  },
  {
    "count": 36,
    "stem": "bust",
    "term": "bust"
  },
  {
    "count": 36,
    "stem": "racism",
    "term": "racism"
  },
  {
    "count": 35,
    "stem": "yemeni",
    "term": "yemeni"
  },
  {
    "count": 35,
    "stem": "adapt",
    "term": "adapt"
  },
  {
    "count": 35,
    "stem": "boo",
    "term": "booed"
  },
  {
    "count": 35,
    "stem": "embark",
    "term": "embarked"
  },
  {
    "count": 35,
    "stem": "icon",
    "term": "icon"
  },
  {
    "count": 35,
    "stem": "tick",
    "term": "ticked"
  },
  {
    "count": 35,
    "stem": "distress",
    "term": "distress"
  },
  {
    "count": 35,
    "stem": "impeach",
    "term": "impeachment"
  },
  {
    "count": 35,
    "stem": "atroc",
    "term": "atrocities"
  },
  {
    "count": 35,
    "stem": "hong",
    "term": "hong"
  },
  {
    "count": 35,
    "stem": "andrea",
    "term": "andrea"
  },
  {
    "count": 35,
    "stem": "mileston",
    "term": "milestone"
  },
  {
    "count": 35,
    "stem": "refineri",
    "term": "refineries"
  },
  {
    "count": 35,
    "stem": "cybersecur",
    "term": "cybersecurity"
  },
  {
    "count": 35,
    "stem": "arn",
    "term": "arne"
  },
  {
    "count": 35,
    "stem": "dismai",
    "term": "dismayed"
  },
  {
    "count": 35,
    "stem": "sober",
    "term": "sober"
  },
  {
    "count": 35,
    "stem": "subcommitte",
    "term": "subcommittee"
  },
  {
    "count": 35,
    "stem": "herman",
    "term": "herman"
  },
  {
    "count": 35,
    "stem": "auction",
    "term": "auction"
  },
  {
    "count": 35,
    "stem": "speechwrit",
    "term": "speechwriter"
  },
  {
    "count": 35,
    "stem": "cincinnati",
    "term": "cincinnati"
  },
  {
    "count": 35,
    "stem": "jeopard",
    "term": "jeopardize"
  },
  {
    "count": 35,
    "stem": "documentari",
    "term": "documentary"
  },
  {
    "count": 35,
    "stem": "kathleen",
    "term": "kathleen"
  },
  {
    "count": 35,
    "stem": "bibl",
    "term": "bible"
  },
  {
    "count": 35,
    "stem": "carl",
    "term": "carl"
  },
  {
    "count": 35,
    "stem": "vermont",
    "term": "vermont"
  },
  {
    "count": 35,
    "stem": "depriv",
    "term": "deprived"
  },
  {
    "count": 35,
    "stem": "huffington",
    "term": "huffington"
  },
  {
    "count": 35,
    "stem": "bulk",
    "term": "bulk"
  },
  {
    "count": 35,
    "stem": "patron",
    "term": "patron"
  },
  {
    "count": 35,
    "stem": "napolitano",
    "term": "napolitano"
  },
  {
    "count": 35,
    "stem": "donohu",
    "term": "donohue"
  },
  {
    "count": 35,
    "stem": "alloc",
    "term": "allocated"
  },
  {
    "count": 35,
    "stem": "audac",
    "term": "audacity"
  },
  {
    "count": 35,
    "stem": "timid",
    "term": "timid"
  },
  {
    "count": 35,
    "stem": "veil",
    "term": "veiled"
  },
  {
    "count": 35,
    "stem": "overtur",
    "term": "overture"
  },
  {
    "count": 35,
    "stem": "beltwai",
    "term": "beltway"
  },
  {
    "count": 34,
    "stem": "passiv",
    "term": "passive"
  },
  {
    "count": 34,
    "stem": "lisbon",
    "term": "lisbon"
  },
  {
    "count": 34,
    "stem": "mcchrystal",
    "term": "mcchrystal"
  },
  {
    "count": 34,
    "stem": "drawdown",
    "term": "drawdown"
  },
  {
    "count": 34,
    "stem": "likabl",
    "term": "likable"
  },
  {
    "count": 34,
    "stem": "petroleum",
    "term": "petroleum"
  },
  {
    "count": 34,
    "stem": "analyz",
    "term": "analyzed"
  },
  {
    "count": 34,
    "stem": "statutori",
    "term": "statutory"
  },
  {
    "count": 34,
    "stem": "weari",
    "term": "weary"
  },
  {
    "count": 34,
    "stem": "ceas",
    "term": "cease"
  },
  {
    "count": 34,
    "stem": "bluntli",
    "term": "bluntly"
  },
  {
    "count": 34,
    "stem": "insult",
    "term": "insult"
  },
  {
    "count": 34,
    "stem": "mute",
    "term": "muted"
  },
  {
    "count": 34,
    "stem": "mall",
    "term": "mall"
  },
  {
    "count": 34,
    "stem": "cornerston",
    "term": "cornerstone"
  },
  {
    "count": 34,
    "stem": "lethal",
    "term": "lethal"
  },
  {
    "count": 34,
    "stem": "calif",
    "term": "calif"
  },
  {
    "count": 34,
    "stem": "cling",
    "term": "cling"
  },
  {
    "count": 34,
    "stem": "marathon",
    "term": "marathon"
  },
  {
    "count": 34,
    "stem": "transcript",
    "term": "transcript"
  },
  {
    "count": 34,
    "stem": "tepid",
    "term": "tepid"
  },
  {
    "count": 34,
    "stem": "earthquak",
    "term": "earthquake"
  },
  {
    "count": 34,
    "stem": "sharpen",
    "term": "sharpened"
  },
  {
    "count": 34,
    "stem": "shed",
    "term": "shed"
  },
  {
    "count": 34,
    "stem": "suppress",
    "term": "suppressing"
  },
  {
    "count": 34,
    "stem": "constraint",
    "term": "constraints"
  },
  {
    "count": 34,
    "stem": "mastermind",
    "term": "mastermind"
  },
  {
    "count": 34,
    "stem": "lengthi",
    "term": "lengthy"
  },
  {
    "count": 34,
    "stem": "cement",
    "term": "cement"
  },
  {
    "count": 34,
    "stem": "obsess",
    "term": "obsession"
  },
  {
    "count": 34,
    "stem": "fred",
    "term": "fred"
  },
  {
    "count": 34,
    "stem": "chariti",
    "term": "charities"
  },
  {
    "count": 34,
    "stem": "dunham",
    "term": "dunham"
  },
  {
    "count": 34,
    "stem": "klein",
    "term": "klein"
  },
  {
    "count": 34,
    "stem": "capitalist",
    "term": "capitalist"
  },
  {
    "count": 34,
    "stem": "dolan",
    "term": "dolan"
  },
  {
    "count": 34,
    "stem": "min",
    "term": "min"
  },
  {
    "count": 34,
    "stem": "packer",
    "term": "packers"
  },
  {
    "count": 34,
    "stem": "todd",
    "term": "todd"
  },
  {
    "count": 34,
    "stem": "circul",
    "term": "circulated"
  },
  {
    "count": 34,
    "stem": "suspici",
    "term": "suspicious"
  },
  {
    "count": 34,
    "stem": "potent",
    "term": "potent"
  },
  {
    "count": 34,
    "stem": "dislik",
    "term": "dislike"
  },
  {
    "count": 33,
    "stem": "halei",
    "term": "haley"
  },
  {
    "count": 33,
    "stem": "kyi",
    "term": "kyi"
  },
  {
    "count": 33,
    "stem": "consent",
    "term": "consent"
  },
  {
    "count": 33,
    "stem": "org",
    "term": "org"
  },
  {
    "count": 33,
    "stem": "lure",
    "term": "lure"
  },
  {
    "count": 33,
    "stem": "jong",
    "term": "jong"
  },
  {
    "count": 33,
    "stem": "khalid",
    "term": "khalid"
  },
  {
    "count": 33,
    "stem": "repositori",
    "term": "repository"
  },
  {
    "count": 33,
    "stem": "panama",
    "term": "panama"
  },
  {
    "count": 33,
    "stem": "boot",
    "term": "boots"
  },
  {
    "count": 33,
    "stem": "hip",
    "term": "hip"
  },
  {
    "count": 33,
    "stem": "chairmen",
    "term": "chairmen"
  },
  {
    "count": 33,
    "stem": "irrespons",
    "term": "irresponsible"
  },
  {
    "count": 33,
    "stem": "eloqu",
    "term": "eloquently"
  },
  {
    "count": 33,
    "stem": "shelv",
    "term": "shelved"
  },
  {
    "count": 33,
    "stem": "cutter",
    "term": "cutter"
  },
  {
    "count": 33,
    "stem": "arkansa",
    "term": "arkansas"
  },
  {
    "count": 33,
    "stem": "discredit",
    "term": "discredit"
  },
  {
    "count": 33,
    "stem": "rebut",
    "term": "rebut"
  },
  {
    "count": 33,
    "stem": "plung",
    "term": "plunge"
  },
  {
    "count": 33,
    "stem": "lebanon",
    "term": "lebanon"
  },
  {
    "count": 33,
    "stem": "nichola",
    "term": "nicholas"
  },
  {
    "count": 33,
    "stem": "waiv",
    "term": "waive"
  },
  {
    "count": 33,
    "stem": "pollut",
    "term": "pollutants"
  },
  {
    "count": 33,
    "stem": "refinanc",
    "term": "refinancing"
  },
  {
    "count": 33,
    "stem": "laura",
    "term": "laura"
  },
  {
    "count": 33,
    "stem": "harbor",
    "term": "harbor"
  },
  {
    "count": 33,
    "stem": "alzheim",
    "term": "alzheimer"
  },
  {
    "count": 33,
    "stem": "wield",
    "term": "wield"
  },
  {
    "count": 33,
    "stem": "dissent",
    "term": "dissent"
  },
  {
    "count": 33,
    "stem": "bia",
    "term": "bias"
  },
  {
    "count": 33,
    "stem": "postelect",
    "term": "postelection"
  },
  {
    "count": 33,
    "stem": "dalla",
    "term": "dallas"
  },
  {
    "count": 33,
    "stem": "canvass",
    "term": "canvassing"
  },
  {
    "count": 33,
    "stem": "won't",
    "term": "won't"
  },
  {
    "count": 33,
    "stem": "abid",
    "term": "abide"
  },
  {
    "count": 33,
    "stem": "solidar",
    "term": "solidarity"
  },
  {
    "count": 33,
    "stem": "sein",
    "term": "sein"
  },
  {
    "count": 33,
    "stem": "suu",
    "term": "suu"
  },
  {
    "count": 33,
    "stem": "solicitor",
    "term": "solicitor"
  },
  {
    "count": 33,
    "stem": "aung",
    "term": "aung"
  },
  {
    "count": 33,
    "stem": "sonia",
    "term": "sonia"
  },
  {
    "count": 33,
    "stem": "sooner",
    "term": "sooner"
  },
  {
    "count": 33,
    "stem": "ethnic",
    "term": "ethnic"
  },
  {
    "count": 33,
    "stem": "drift",
    "term": "drift"
  },
  {
    "count": 33,
    "stem": "likew",
    "term": "likewise"
  },
  {
    "count": 32,
    "stem": "downturn",
    "term": "downturn"
  },
  {
    "count": 32,
    "stem": "intimid",
    "term": "intimidation"
  },
  {
    "count": 32,
    "stem": "solicit",
    "term": "soliciting"
  },
  {
    "count": 32,
    "stem": "robinson",
    "term": "robinson"
  },
  {
    "count": 32,
    "stem": "lender",
    "term": "lenders"
  },
  {
    "count": 32,
    "stem": "embargo",
    "term": "embargo"
  },
  {
    "count": 32,
    "stem": "repay",
    "term": "repayment"
  },
  {
    "count": 32,
    "stem": "vet",
    "term": "vetting"
  },
  {
    "count": 32,
    "stem": "blair",
    "term": "blair"
  },
  {
    "count": 32,
    "stem": "breach",
    "term": "breach"
  },
  {
    "count": 32,
    "stem": "outright",
    "term": "outright"
  },
  {
    "count": 32,
    "stem": "lifetim",
    "term": "lifetime"
  },
  {
    "count": 32,
    "stem": "irrelev",
    "term": "irrelevant"
  },
  {
    "count": 32,
    "stem": "choru",
    "term": "chorus"
  },
  {
    "count": 32,
    "stem": "immun",
    "term": "immunity"
  },
  {
    "count": 32,
    "stem": "fake",
    "term": "fake"
  },
  {
    "count": 32,
    "stem": "politic",
    "term": "politicizing"
  },
  {
    "count": 32,
    "stem": "cardin",
    "term": "cardinal"
  },
  {
    "count": 32,
    "stem": "hardship",
    "term": "hardship"
  },
  {
    "count": 32,
    "stem": "epic",
    "term": "epic"
  },
  {
    "count": 32,
    "stem": "loyalist",
    "term": "loyalists"
  },
  {
    "count": 32,
    "stem": "ozon",
    "term": "ozone"
  },
  {
    "count": 32,
    "stem": "pyongyang",
    "term": "pyongyang"
  },
  {
    "count": 32,
    "stem": "bend",
    "term": "bend"
  },
  {
    "count": 32,
    "stem": "savag",
    "term": "savage"
  },
  {
    "count": 32,
    "stem": "seneg",
    "term": "senegal"
  },
  {
    "count": 32,
    "stem": "indefinit",
    "term": "indefinite"
  },
  {
    "count": 32,
    "stem": "protract",
    "term": "protracted"
  },
  {
    "count": 32,
    "stem": "trickl",
    "term": "trickle"
  },
  {
    "count": 32,
    "stem": "dunn",
    "term": "dunn"
  },
  {
    "count": 32,
    "stem": "singer",
    "term": "singer"
  },
  {
    "count": 32,
    "stem": "airwav",
    "term": "airwaves"
  },
  {
    "count": 32,
    "stem": "imperil",
    "term": "imperil"
  },
  {
    "count": 32,
    "stem": "unchang",
    "term": "unchanged"
  },
  {
    "count": 32,
    "stem": "fluke",
    "term": "fluke"
  },
  {
    "count": 32,
    "stem": "aloof",
    "term": "aloof"
  },
  {
    "count": 32,
    "stem": "alberta",
    "term": "alberta"
  },
  {
    "count": 32,
    "stem": "leaker",
    "term": "leakers"
  },
  {
    "count": 32,
    "stem": "inclus",
    "term": "inclusive"
  },
  {
    "count": 32,
    "stem": "singular",
    "term": "singular"
  },
  {
    "count": 32,
    "stem": "remedi",
    "term": "remedies"
  },
  {
    "count": 32,
    "stem": "podium",
    "term": "podium"
  },
  {
    "count": 32,
    "stem": "espionag",
    "term": "espionage"
  },
  {
    "count": 31,
    "stem": "impati",
    "term": "impatient"
  },
  {
    "count": 31,
    "stem": "louri",
    "term": "loury"
  },
  {
    "count": 31,
    "stem": "ricin",
    "term": "ricin"
  },
  {
    "count": 31,
    "stem": "fallon",
    "term": "fallon"
  },
  {
    "count": 31,
    "stem": "steal",
    "term": "steal"
  },
  {
    "count": 31,
    "stem": "brace",
    "term": "bracing"
  },
  {
    "count": 31,
    "stem": "jess",
    "term": "jesse"
  },
  {
    "count": 31,
    "stem": "truman",
    "term": "truman"
  },
  {
    "count": 31,
    "stem": "termin",
    "term": "terminate"
  },
  {
    "count": 31,
    "stem": "ovat",
    "term": "ovation"
  },
  {
    "count": 31,
    "stem": "sharpest",
    "term": "sharpest"
  },
  {
    "count": 31,
    "stem": "championship",
    "term": "championship"
  },
  {
    "count": 31,
    "stem": "relianc",
    "term": "reliance"
  },
  {
    "count": 31,
    "stem": "intransig",
    "term": "intransigence"
  },
  {
    "count": 31,
    "stem": "bureaucrat",
    "term": "bureaucratic"
  },
  {
    "count": 31,
    "stem": "scold",
    "term": "scolded"
  },
  {
    "count": 31,
    "stem": "dash",
    "term": "dashed"
  },
  {
    "count": 31,
    "stem": "gala",
    "term": "gala"
  },
  {
    "count": 31,
    "stem": "ruin",
    "term": "ruin"
  },
  {
    "count": 31,
    "stem": "refuge",
    "term": "refugees"
  },
  {
    "count": 31,
    "stem": "hack",
    "term": "hacking"
  },
  {
    "count": 31,
    "stem": "mantl",
    "term": "mantle"
  },
  {
    "count": 31,
    "stem": "greek",
    "term": "greek"
  },
  {
    "count": 31,
    "stem": "consolid",
    "term": "consolidate"
  },
  {
    "count": 31,
    "stem": "debut",
    "term": "debut"
  },
  {
    "count": 31,
    "stem": "mend",
    "term": "mend"
  },
  {
    "count": 31,
    "stem": "khamenei",
    "term": "khamenei"
  },
  {
    "count": 31,
    "stem": "faction",
    "term": "factions"
  },
  {
    "count": 31,
    "stem": "bernard",
    "term": "bernard"
  },
  {
    "count": 31,
    "stem": "inabl",
    "term": "inability"
  },
  {
    "count": 31,
    "stem": "howard",
    "term": "howard"
  },
  {
    "count": 31,
    "stem": "trumka",
    "term": "trumka"
  },
  {
    "count": 31,
    "stem": "nonsens",
    "term": "nonsense"
  },
  {
    "count": 31,
    "stem": "resili",
    "term": "resilience"
  },
  {
    "count": 31,
    "stem": "collabor",
    "term": "collaboration"
  },
  {
    "count": 31,
    "stem": "buoi",
    "term": "buoyed"
  },
  {
    "count": 31,
    "stem": "arlington",
    "term": "arlington"
  },
  {
    "count": 31,
    "stem": "exceed",
    "term": "exceeded"
  },
  {
    "count": 31,
    "stem": "harden",
    "term": "hardened"
  },
  {
    "count": 31,
    "stem": "pen",
    "term": "pen"
  },
  {
    "count": 31,
    "stem": "portman",
    "term": "portman"
  },
  {
    "count": 31,
    "stem": "withdrew",
    "term": "withdrew"
  },
  {
    "count": 31,
    "stem": "espn",
    "term": "espn"
  },
  {
    "count": 31,
    "stem": "arrog",
    "term": "arrogant"
  },
  {
    "count": 31,
    "stem": "italian",
    "term": "italian"
  },
  {
    "count": 31,
    "stem": "demon",
    "term": "demonize"
  },
  {
    "count": 31,
    "stem": "megan",
    "term": "megan"
  },
  {
    "count": 31,
    "stem": "shy",
    "term": "shy"
  },
  {
    "count": 31,
    "stem": "prolong",
    "term": "prolonged"
  },
  {
    "count": 31,
    "stem": "thein",
    "term": "thein"
  },
  {
    "count": 31,
    "stem": "playbook",
    "term": "playbook"
  },
  {
    "count": 30,
    "stem": "hezbollah",
    "term": "hezbollah"
  },
  {
    "count": 30,
    "stem": "fret",
    "term": "fretted"
  },
  {
    "count": 30,
    "stem": "perpetu",
    "term": "perpetual"
  },
  {
    "count": 30,
    "stem": "friction",
    "term": "friction"
  },
  {
    "count": 30,
    "stem": "assang",
    "term": "assange"
  },
  {
    "count": 30,
    "stem": "suicid",
    "term": "suicide"
  },
  {
    "count": 30,
    "stem": "transcend",
    "term": "transcend"
  },
  {
    "count": 30,
    "stem": "toll",
    "term": "toll"
  },
  {
    "count": 30,
    "stem": "burma",
    "term": "burma"
  },
  {
    "count": 30,
    "stem": "dishonest",
    "term": "dishonest"
  },
  {
    "count": 30,
    "stem": "warrior",
    "term": "warrior"
  },
  {
    "count": 30,
    "stem": "thrive",
    "term": "thriving"
  },
  {
    "count": 30,
    "stem": "heighten",
    "term": "heightened"
  },
  {
    "count": 30,
    "stem": "onetim",
    "term": "onetime"
  },
  {
    "count": 30,
    "stem": "mcdonough",
    "term": "mcdonough"
  },
  {
    "count": 30,
    "stem": "hybrid",
    "term": "hybrid"
  },
  {
    "count": 30,
    "stem": "funer",
    "term": "funeral"
  },
  {
    "count": 30,
    "stem": "tuition",
    "term": "tuition"
  },
  {
    "count": 30,
    "stem": "aloud",
    "term": "aloud"
  },
  {
    "count": 30,
    "stem": "pena",
    "term": "pena"
  },
  {
    "count": 30,
    "stem": "suskind",
    "term": "suskind"
  },
  {
    "count": 30,
    "stem": "lectern",
    "term": "lectern"
  },
  {
    "count": 30,
    "stem": "terri",
    "term": "terry"
  },
  {
    "count": 30,
    "stem": "persian",
    "term": "persian"
  },
  {
    "count": 30,
    "stem": "stronghold",
    "term": "stronghold"
  },
  {
    "count": 30,
    "stem": "boil",
    "term": "boiled"
  },
  {
    "count": 30,
    "stem": "candi",
    "term": "candy"
  },
  {
    "count": 30,
    "stem": "i'm",
    "term": "i'm"
  },
  {
    "count": 30,
    "stem": "oscar",
    "term": "oscar"
  },
  {
    "count": 30,
    "stem": "indonesian",
    "term": "indonesian"
  },
  {
    "count": 30,
    "stem": "austan",
    "term": "austan"
  },
  {
    "count": 30,
    "stem": "chef",
    "term": "chef"
  },
  {
    "count": 30,
    "stem": "fend",
    "term": "fend"
  },
  {
    "count": 30,
    "stem": "palestin",
    "term": "palestine"
  },
  {
    "count": 30,
    "stem": "renomin",
    "term": "renominate"
  },
  {
    "count": 30,
    "stem": "falter",
    "term": "faltering"
  },
  {
    "count": 30,
    "stem": "attende",
    "term": "attendees"
  },
  {
    "count": 30,
    "stem": "coher",
    "term": "coherent"
  },
  {
    "count": 30,
    "stem": "bumper",
    "term": "bumper"
  },
  {
    "count": 30,
    "stem": "decor",
    "term": "decorated"
  },
  {
    "count": 30,
    "stem": "pave",
    "term": "pave"
  },
  {
    "count": 30,
    "stem": "bureaucraci",
    "term": "bureaucracy"
  },
  {
    "count": 30,
    "stem": "gregori",
    "term": "gregory"
  },
  {
    "count": 30,
    "stem": "unseat",
    "term": "unseat"
  },
  {
    "count": 30,
    "stem": "lavish",
    "term": "lavish"
  },
  {
    "count": 30,
    "stem": "lace",
    "term": "laced"
  },
  {
    "count": 29,
    "stem": "stifl",
    "term": "stifling"
  },
  {
    "count": 29,
    "stem": "instinct",
    "term": "instincts"
  },
  {
    "count": 29,
    "stem": "bak",
    "term": "bak"
  },
  {
    "count": 29,
    "stem": "advisor",
    "term": "advisors"
  },
  {
    "count": 29,
    "stem": "pere",
    "term": "peres"
  },
  {
    "count": 29,
    "stem": "pdf",
    "term": "pdf"
  },
  {
    "count": 29,
    "stem": "dip",
    "term": "dip"
  },
  {
    "count": 29,
    "stem": "grace",
    "term": "grace"
  },
  {
    "count": 29,
    "stem": "redistribut",
    "term": "redistribution"
  },
  {
    "count": 29,
    "stem": "vehem",
    "term": "vehemently"
  },
  {
    "count": 29,
    "stem": "lugar",
    "term": "lugar"
  },
  {
    "count": 29,
    "stem": "mogul",
    "term": "mogul"
  },
  {
    "count": 29,
    "stem": "sincer",
    "term": "sincere"
  },
  {
    "count": 29,
    "stem": "guardian",
    "term": "guardian"
  },
  {
    "count": 29,
    "stem": "predat",
    "term": "predator"
  },
  {
    "count": 29,
    "stem": "systemat",
    "term": "systematically"
  },
  {
    "count": 29,
    "stem": "toni",
    "term": "tony"
  },
  {
    "count": 29,
    "stem": "abruptli",
    "term": "abruptly"
  },
  {
    "count": 29,
    "stem": "sunstein",
    "term": "sunstein"
  },
  {
    "count": 29,
    "stem": "seattl",
    "term": "seattle"
  },
  {
    "count": 29,
    "stem": "lacklust",
    "term": "lackluster"
  },
  {
    "count": 29,
    "stem": "foil",
    "term": "foil"
  },
  {
    "count": 29,
    "stem": "fractur",
    "term": "fractured"
  },
  {
    "count": 29,
    "stem": "hanniti",
    "term": "hannity"
  },
  {
    "count": 29,
    "stem": "tower",
    "term": "tower"
  },
  {
    "count": 29,
    "stem": "overdu",
    "term": "overdue"
  },
  {
    "count": 29,
    "stem": "myung",
    "term": "myung"
  },
  {
    "count": 29,
    "stem": "kirsten",
    "term": "kirsten"
  },
  {
    "count": 29,
    "stem": "elud",
    "term": "eluded"
  },
  {
    "count": 29,
    "stem": "insert",
    "term": "inserted"
  },
  {
    "count": 29,
    "stem": "antitrust",
    "term": "antitrust"
  },
  {
    "count": 29,
    "stem": "funni",
    "term": "funny"
  },
  {
    "count": 29,
    "stem": "verifi",
    "term": "verify"
  },
  {
    "count": 29,
    "stem": "singh",
    "term": "singh"
  },
  {
    "count": 29,
    "stem": "qatar",
    "term": "qatar"
  },
  {
    "count": 29,
    "stem": "newark",
    "term": "newark"
  },
  {
    "count": 29,
    "stem": "bloodsh",
    "term": "bloodshed"
  },
  {
    "count": 29,
    "stem": "uphil",
    "term": "uphill"
  },
  {
    "count": 29,
    "stem": "overlook",
    "term": "overlooking"
  },
  {
    "count": 29,
    "stem": "distrust",
    "term": "distrust"
  },
  {
    "count": 29,
    "stem": "ail",
    "term": "ailes"
  },
  {
    "count": 29,
    "stem": "bubbl",
    "term": "bubble"
  },
  {
    "count": 29,
    "stem": "entiti",
    "term": "entity"
  },
  {
    "count": 29,
    "stem": "prostitut",
    "term": "prostitutes"
  },
  {
    "count": 29,
    "stem": "hypocrisi",
    "term": "hypocrisy"
  },
  {
    "count": 29,
    "stem": "shortag",
    "term": "shortages"
  },
  {
    "count": 29,
    "stem": "tripl",
    "term": "triple"
  },
  {
    "count": 29,
    "stem": "underestim",
    "term": "underestimated"
  },
  {
    "count": 29,
    "stem": "marc",
    "term": "marc"
  },
  {
    "count": 29,
    "stem": "subpoena",
    "term": "subpoenas"
  },
  {
    "count": 29,
    "stem": "tempt",
    "term": "tempted"
  },
  {
    "count": 29,
    "stem": "forgotten",
    "term": "forgotten"
  },
  {
    "count": 29,
    "stem": "emphat",
    "term": "emphatically"
  },
  {
    "count": 29,
    "stem": "spike",
    "term": "spike"
  },
  {
    "count": 29,
    "stem": "coburn",
    "term": "coburn"
  },
  {
    "count": 29,
    "stem": "princeton",
    "term": "princeton"
  },
  {
    "count": 29,
    "stem": "barb",
    "term": "barbs"
  },
  {
    "count": 29,
    "stem": "batter",
    "term": "battered"
  },
  {
    "count": 29,
    "stem": "unlimit",
    "term": "unlimited"
  },
  {
    "count": 29,
    "stem": "inconsist",
    "term": "inconsistent"
  },
  {
    "count": 29,
    "stem": "shipment",
    "term": "shipments"
  },
  {
    "count": 29,
    "stem": "baltimor",
    "term": "baltimore"
  },
  {
    "count": 29,
    "stem": "pounc",
    "term": "pounced"
  },
  {
    "count": 29,
    "stem": "ploi",
    "term": "ploy"
  },
  {
    "count": 29,
    "stem": "provinc",
    "term": "province"
  },
  {
    "count": 29,
    "stem": "australian",
    "term": "australian"
  },
  {
    "count": 29,
    "stem": "dissid",
    "term": "dissident"
  },
  {
    "count": 29,
    "stem": "repatri",
    "term": "repatriate"
  },
  {
    "count": 29,
    "stem": "flop",
    "term": "flopping"
  },
  {
    "count": 29,
    "stem": "japanes",
    "term": "japanese"
  },
  {
    "count": 28,
    "stem": "exce",
    "term": "exceed"
  },
  {
    "count": 28,
    "stem": "vigil",
    "term": "vigilant"
  },
  {
    "count": 28,
    "stem": "compil",
    "term": "compiled"
  },
  {
    "count": 28,
    "stem": "debacl",
    "term": "debacle"
  },
  {
    "count": 28,
    "stem": "prolifer",
    "term": "proliferation"
  },
  {
    "count": 28,
    "stem": "evok",
    "term": "evoked"
  },
  {
    "count": 28,
    "stem": "countless",
    "term": "countless"
  },
  {
    "count": 28,
    "stem": "messi",
    "term": "messy"
  },
  {
    "count": 28,
    "stem": "ayatollah",
    "term": "ayatollah"
  },
  {
    "count": 28,
    "stem": "drum",
    "term": "drum"
  },
  {
    "count": 28,
    "stem": "relentlessli",
    "term": "relentlessly"
  },
  {
    "count": 28,
    "stem": "misstep",
    "term": "missteps"
  },
  {
    "count": 28,
    "stem": "murrai",
    "term": "murray"
  },
  {
    "count": 28,
    "stem": "bash",
    "term": "bashing"
  },
  {
    "count": 28,
    "stem": "toi",
    "term": "toy"
  },
  {
    "count": 28,
    "stem": "tack",
    "term": "tack"
  },
  {
    "count": 28,
    "stem": "wrangl",
    "term": "wrangling"
  },
  {
    "count": 28,
    "stem": "sharif",
    "term": "sharif"
  },
  {
    "count": 28,
    "stem": "sprawl",
    "term": "sprawling"
  },
  {
    "count": 28,
    "stem": "roundtabl",
    "term": "roundtable"
  },
  {
    "count": 28,
    "stem": "grasslei",
    "term": "grassley"
  },
  {
    "count": 28,
    "stem": "veer",
    "term": "veered"
  },
  {
    "count": 28,
    "stem": "liar",
    "term": "liar"
  },
  {
    "count": 28,
    "stem": "secular",
    "term": "secular"
  },
  {
    "count": 28,
    "stem": "toledo",
    "term": "toledo"
  },
  {
    "count": 28,
    "stem": "slave",
    "term": "slave"
  },
  {
    "count": 28,
    "stem": "premis",
    "term": "premise"
  },
  {
    "count": 28,
    "stem": "wane",
    "term": "waning"
  },
  {
    "count": 28,
    "stem": "inact",
    "term": "inaction"
  },
  {
    "count": 28,
    "stem": "reinstat",
    "term": "reinstate"
  },
  {
    "count": 28,
    "stem": "multilater",
    "term": "multilateral"
  },
  {
    "count": 28,
    "stem": "tribe",
    "term": "tribe"
  },
  {
    "count": 28,
    "stem": "unfairli",
    "term": "unfairly"
  },
  {
    "count": 28,
    "stem": "dispar",
    "term": "disparity"
  },
  {
    "count": 28,
    "stem": "mediat",
    "term": "mediator"
  },
  {
    "count": 28,
    "stem": "rican",
    "term": "rican"
  },
  {
    "count": 28,
    "stem": "replic",
    "term": "replicate"
  },
  {
    "count": 28,
    "stem": "ponder",
    "term": "pondering"
  },
  {
    "count": 28,
    "stem": "whenev",
    "term": "whenever"
  },
  {
    "count": 28,
    "stem": "jakarta",
    "term": "jakarta"
  },
  {
    "count": 28,
    "stem": "phoni",
    "term": "phony"
  },
  {
    "count": 28,
    "stem": "cautious",
    "term": "cautiously"
  },
  {
    "count": 28,
    "stem": "brazilian",
    "term": "brazilian"
  },
  {
    "count": 28,
    "stem": "jennif",
    "term": "jennifer"
  },
  {
    "count": 28,
    "stem": "chafe",
    "term": "chafee"
  },
  {
    "count": 28,
    "stem": "evacu",
    "term": "evacuation"
  },
  {
    "count": 28,
    "stem": "watchdog",
    "term": "watchdog"
  },
  {
    "count": 28,
    "stem": "ramo",
    "term": "ramos"
  },
  {
    "count": 28,
    "stem": "royal",
    "term": "royal"
  },
  {
    "count": 28,
    "stem": "slump",
    "term": "slump"
  },
  {
    "count": 28,
    "stem": "ahmadinejad",
    "term": "ahmadinejad"
  },
  {
    "count": 28,
    "stem": "unanim",
    "term": "unanimous"
  },
  {
    "count": 27,
    "stem": "indecis",
    "term": "indecisive"
  },
  {
    "count": 27,
    "stem": "cruz",
    "term": "cruz"
  },
  {
    "count": 27,
    "stem": "relish",
    "term": "relish"
  },
  {
    "count": 27,
    "stem": "hawkish",
    "term": "hawkish"
  },
  {
    "count": 27,
    "stem": "elbow",
    "term": "elbow"
  },
  {
    "count": 27,
    "stem": "czar",
    "term": "czar"
  },
  {
    "count": 27,
    "stem": "squeez",
    "term": "squeeze"
  },
  {
    "count": 27,
    "stem": "mentor",
    "term": "mentor"
  },
  {
    "count": 27,
    "stem": "nail",
    "term": "nail"
  },
  {
    "count": 27,
    "stem": "logist",
    "term": "logistical"
  },
  {
    "count": 27,
    "stem": "comedian",
    "term": "comedian"
  },
  {
    "count": 27,
    "stem": "pushback",
    "term": "pushback"
  },
  {
    "count": 27,
    "stem": "madison",
    "term": "madison"
  },
  {
    "count": 27,
    "stem": "didn't",
    "term": "didn't"
  },
  {
    "count": 27,
    "stem": "phillip",
    "term": "phillips"
  },
  {
    "count": 27,
    "stem": "grievanc",
    "term": "grievances"
  },
  {
    "count": 27,
    "stem": "waver",
    "term": "wavering"
  },
  {
    "count": 27,
    "stem": "griffin",
    "term": "griffin"
  },
  {
    "count": 27,
    "stem": "talli",
    "term": "tally"
  },
  {
    "count": 27,
    "stem": "disadvantag",
    "term": "disadvantage"
  },
  {
    "count": 27,
    "stem": "mcardl",
    "term": "mcardle"
  },
  {
    "count": 27,
    "stem": "aaron",
    "term": "aaron"
  },
  {
    "count": 27,
    "stem": "alexand",
    "term": "alexander"
  },
  {
    "count": 27,
    "stem": "vacant",
    "term": "vacant"
  },
  {
    "count": 27,
    "stem": "ratchet",
    "term": "ratchet"
  },
  {
    "count": 27,
    "stem": "cartagena",
    "term": "cartagena"
  },
  {
    "count": 27,
    "stem": "tweak",
    "term": "tweak"
  },
  {
    "count": 27,
    "stem": "lord",
    "term": "lord"
  },
  {
    "count": 27,
    "stem": "calculu",
    "term": "calculus"
  },
  {
    "count": 27,
    "stem": "daunt",
    "term": "daunting"
  },
  {
    "count": 27,
    "stem": "disproportion",
    "term": "disproportionately"
  },
  {
    "count": 27,
    "stem": "acced",
    "term": "accede"
  },
  {
    "count": 27,
    "stem": "contempt",
    "term": "contempt"
  },
  {
    "count": 27,
    "stem": "mosqu",
    "term": "mosque"
  },
  {
    "count": 27,
    "stem": "dividend",
    "term": "dividends"
  },
  {
    "count": 27,
    "stem": "ambival",
    "term": "ambivalence"
  },
  {
    "count": 27,
    "stem": "mcdonnel",
    "term": "mcdonnell"
  },
  {
    "count": 27,
    "stem": "mantra",
    "term": "mantra"
  },
  {
    "count": 27,
    "stem": "conservat",
    "term": "conservatism"
  },
  {
    "count": 27,
    "stem": "jesu",
    "term": "jesus"
  },
  {
    "count": 27,
    "stem": "withdrawn",
    "term": "withdrawn"
  },
  {
    "count": 27,
    "stem": "outpost",
    "term": "outposts"
  },
  {
    "count": 27,
    "stem": "slice",
    "term": "slice"
  },
  {
    "count": 27,
    "stem": "shaikh",
    "term": "shaikh"
  },
  {
    "count": 27,
    "stem": "minu",
    "term": "minus"
  },
  {
    "count": 27,
    "stem": "layoff",
    "term": "layoffs"
  },
  {
    "count": 27,
    "stem": "hadn",
    "term": "hadn"
  },
  {
    "count": 27,
    "stem": "samantha",
    "term": "samantha"
  },
  {
    "count": 27,
    "stem": "premier",
    "term": "premier"
  },
  {
    "count": 27,
    "stem": "thailand",
    "term": "thailand"
  },
  {
    "count": 27,
    "stem": "houston",
    "term": "houston"
  },
  {
    "count": 27,
    "stem": "volcker",
    "term": "volcker"
  },
  {
    "count": 27,
    "stem": "sizabl",
    "term": "sizable"
  },
  {
    "count": 27,
    "stem": "rigor",
    "term": "rigorous"
  },
  {
    "count": 27,
    "stem": "sabotag",
    "term": "sabotage"
  },
  {
    "count": 27,
    "stem": "psaki",
    "term": "psaki"
  },
  {
    "count": 27,
    "stem": "loosen",
    "term": "loosen"
  },
  {
    "count": 27,
    "stem": "gordon",
    "term": "gordon"
  },
  {
    "count": 26,
    "stem": "pummel",
    "term": "pummeled"
  },
  {
    "count": 26,
    "stem": "brussel",
    "term": "brussels"
  },
  {
    "count": 26,
    "stem": "barak",
    "term": "barak"
  },
  {
    "count": 26,
    "stem": "cnbc",
    "term": "cnbc"
  },
  {
    "count": 26,
    "stem": "minneapoli",
    "term": "minneapolis"
  },
  {
    "count": 26,
    "stem": "fervent",
    "term": "fervent"
  },
  {
    "count": 26,
    "stem": "greenwir",
    "term": "greenwire"
  },
  {
    "count": 26,
    "stem": "albeit",
    "term": "albeit"
  },
  {
    "count": 26,
    "stem": "outcri",
    "term": "outcry"
  },
  {
    "count": 26,
    "stem": "accumul",
    "term": "accumulated"
  },
  {
    "count": 26,
    "stem": "persuas",
    "term": "persuasively"
  },
  {
    "count": 26,
    "stem": "aipac",
    "term": "aipac"
  },
  {
    "count": 26,
    "stem": "jose",
    "term": "jose"
  },
  {
    "count": 26,
    "stem": "wartim",
    "term": "wartime"
  },
  {
    "count": 26,
    "stem": "slower",
    "term": "slower"
  },
  {
    "count": 26,
    "stem": "luke",
    "term": "luke"
  },
  {
    "count": 26,
    "stem": "irish",
    "term": "irish"
  },
  {
    "count": 26,
    "stem": "parker",
    "term": "parker"
  },
  {
    "count": 26,
    "stem": "formul",
    "term": "formulation"
  },
  {
    "count": 26,
    "stem": "hing",
    "term": "hinge"
  },
  {
    "count": 26,
    "stem": "rod",
    "term": "rod"
  },
  {
    "count": 26,
    "stem": "retire",
    "term": "retirees"
  },
  {
    "count": 26,
    "stem": "unsustain",
    "term": "unsustainable"
  },
  {
    "count": 26,
    "stem": "pope",
    "term": "pope"
  },
  {
    "count": 26,
    "stem": "exagger",
    "term": "exaggerated"
  },
  {
    "count": 26,
    "stem": "broadwai",
    "term": "broadway"
  },
  {
    "count": 26,
    "stem": "richest",
    "term": "richest"
  },
  {
    "count": 26,
    "stem": "templ",
    "term": "temple"
  },
  {
    "count": 26,
    "stem": "covet",
    "term": "coveted"
  },
  {
    "count": 26,
    "stem": "sue",
    "term": "sue"
  },
  {
    "count": 26,
    "stem": "whoever",
    "term": "whoever"
  },
  {
    "count": 26,
    "stem": "eastwood",
    "term": "eastwood"
  },
  {
    "count": 26,
    "stem": "counselor",
    "term": "counselor"
  },
  {
    "count": 26,
    "stem": "mcauliff",
    "term": "mcauliffe"
  },
  {
    "count": 26,
    "stem": "militarili",
    "term": "militarily"
  },
  {
    "count": 26,
    "stem": "dougla",
    "term": "douglas"
  },
  {
    "count": 26,
    "stem": "victor",
    "term": "victor"
  },
  {
    "count": 26,
    "stem": "inmat",
    "term": "inmates"
  },
  {
    "count": 26,
    "stem": "loath",
    "term": "loath"
  },
  {
    "count": 26,
    "stem": "sympath",
    "term": "sympathize"
  },
  {
    "count": 26,
    "stem": "sear",
    "term": "searing"
  },
  {
    "count": 26,
    "stem": "effus",
    "term": "effusive"
  },
  {
    "count": 26,
    "stem": "mom",
    "term": "mom"
  },
  {
    "count": 26,
    "stem": "orbit",
    "term": "orbit"
  },
  {
    "count": 26,
    "stem": "chill",
    "term": "chill"
  },
  {
    "count": 26,
    "stem": "ardent",
    "term": "ardent"
  },
  {
    "count": 26,
    "stem": "soro",
    "term": "soros"
  },
  {
    "count": 26,
    "stem": "zient",
    "term": "zients"
  },
  {
    "count": 26,
    "stem": "boe",
    "term": "boeing"
  },
  {
    "count": 26,
    "stem": "quip",
    "term": "quipped"
  },
  {
    "count": 26,
    "stem": "protocol",
    "term": "protocol"
  },
  {
    "count": 26,
    "stem": "undertak",
    "term": "undertake"
  },
  {
    "count": 26,
    "stem": "joplin",
    "term": "joplin"
  },
  {
    "count": 26,
    "stem": "har",
    "term": "harness"
  },
  {
    "count": 26,
    "stem": "weaker",
    "term": "weaker"
  },
  {
    "count": 26,
    "stem": "oliv",
    "term": "olive"
  },
  {
    "count": 26,
    "stem": "annoi",
    "term": "annoyed"
  },
  {
    "count": 26,
    "stem": "lisa",
    "term": "lisa"
  },
  {
    "count": 26,
    "stem": "ironi",
    "term": "irony"
  },
  {
    "count": 26,
    "stem": "ballroom",
    "term": "ballroom"
  },
  {
    "count": 26,
    "stem": "astronaut",
    "term": "astronauts"
  },
  {
    "count": 26,
    "stem": "physician",
    "term": "physician"
  },
  {
    "count": 26,
    "stem": "austin",
    "term": "austin"
  },
  {
    "count": 26,
    "stem": "economix",
    "term": "economix"
  },
  {
    "count": 26,
    "stem": "tangl",
    "term": "tangled"
  },
  {
    "count": 26,
    "stem": "pullout",
    "term": "pullout"
  },
  {
    "count": 26,
    "stem": "exhort",
    "term": "exhorting"
  },
  {
    "count": 26,
    "stem": "simplifi",
    "term": "simplify"
  },
  {
    "count": 26,
    "stem": "defus",
    "term": "defuse"
  },
  {
    "count": 26,
    "stem": "disconnect",
    "term": "disconnect"
  },
  {
    "count": 25,
    "stem": "muddl",
    "term": "muddled"
  },
  {
    "count": 25,
    "stem": "facilit",
    "term": "facilitate"
  },
  {
    "count": 25,
    "stem": "chunk",
    "term": "chunk"
  },
  {
    "count": 25,
    "stem": "baucu",
    "term": "baucus"
  },
  {
    "count": 25,
    "stem": "levin",
    "term": "levin"
  },
  {
    "count": 25,
    "stem": "duke",
    "term": "duke"
  },
  {
    "count": 25,
    "stem": "gimmick",
    "term": "gimmick"
  },
  {
    "count": 25,
    "stem": "idaho",
    "term": "idaho"
  },
  {
    "count": 25,
    "stem": "genocid",
    "term": "genocide"
  },
  {
    "count": 25,
    "stem": "emir",
    "term": "emirates"
  },
  {
    "count": 25,
    "stem": "hardest",
    "term": "hardest"
  },
  {
    "count": 25,
    "stem": "yahoo",
    "term": "yahoo"
  },
  {
    "count": 25,
    "stem": "realm",
    "term": "realm"
  },
  {
    "count": 25,
    "stem": "galvan",
    "term": "galvanized"
  },
  {
    "count": 25,
    "stem": "stopgap",
    "term": "stopgap"
  },
  {
    "count": 25,
    "stem": "headwai",
    "term": "headway"
  },
  {
    "count": 25,
    "stem": "farewel",
    "term": "farewell"
  },
  {
    "count": 25,
    "stem": "confidenti",
    "term": "confidential"
  },
  {
    "count": 25,
    "stem": "steelwork",
    "term": "steelworkers"
  },
  {
    "count": 25,
    "stem": "loser",
    "term": "losers"
  },
  {
    "count": 25,
    "stem": "sluggish",
    "term": "sluggish"
  },
  {
    "count": 25,
    "stem": "lewi",
    "term": "lewis"
  },
  {
    "count": 25,
    "stem": "jen",
    "term": "jen"
  },
  {
    "count": 25,
    "stem": "zuckerberg",
    "term": "zuckerberg"
  },
  {
    "count": 25,
    "stem": "simmer",
    "term": "simmering"
  },
  {
    "count": 25,
    "stem": "penal",
    "term": "penalize"
  },
  {
    "count": 25,
    "stem": "campus",
    "term": "campuses"
  },
  {
    "count": 25,
    "stem": "stapl",
    "term": "staple"
  },
  {
    "count": 25,
    "stem": "diamond",
    "term": "diamond"
  },
  {
    "count": 25,
    "stem": "survivor",
    "term": "survivor"
  },
  {
    "count": 25,
    "stem": "roseland",
    "term": "roseland"
  },
  {
    "count": 25,
    "stem": "rattl",
    "term": "rattling"
  },
  {
    "count": 25,
    "stem": "overrul",
    "term": "overruled"
  },
  {
    "count": 25,
    "stem": "shuttl",
    "term": "shuttle"
  },
  {
    "count": 25,
    "stem": "vex",
    "term": "vexing"
  },
  {
    "count": 25,
    "stem": "wither",
    "term": "withering"
  },
  {
    "count": 25,
    "stem": "mumbai",
    "term": "mumbai"
  },
  {
    "count": 25,
    "stem": "katrina",
    "term": "katrina"
  },
  {
    "count": 25,
    "stem": "pollard",
    "term": "pollard"
  },
  {
    "count": 25,
    "stem": "ruler",
    "term": "rulers"
  },
  {
    "count": 25,
    "stem": "friedman",
    "term": "friedman"
  },
  {
    "count": 25,
    "stem": "debbi",
    "term": "debbie"
  },
  {
    "count": 25,
    "stem": "haqqani",
    "term": "haqqani"
  },
  {
    "count": 25,
    "stem": "wilder",
    "term": "wilderness"
  },
  {
    "count": 25,
    "stem": "circumv",
    "term": "circumvent"
  },
  {
    "count": 25,
    "stem": "prai",
    "term": "pray"
  },
  {
    "count": 25,
    "stem": "abbottabad",
    "term": "abbottabad"
  },
  {
    "count": 25,
    "stem": "pittsburgh",
    "term": "pittsburgh"
  },
  {
    "count": 25,
    "stem": "complianc",
    "term": "compliance"
  },
  {
    "count": 25,
    "stem": "groundwork",
    "term": "groundwork"
  },
  {
    "count": 25,
    "stem": "clout",
    "term": "clout"
  },
  {
    "count": 25,
    "stem": "preschool",
    "term": "preschool"
  },
  {
    "count": 25,
    "stem": "implicit",
    "term": "implicit"
  },
  {
    "count": 25,
    "stem": "ami",
    "term": "amy"
  },
  {
    "count": 25,
    "stem": "sketch",
    "term": "sketch"
  },
  {
    "count": 25,
    "stem": "anem",
    "term": "anemic"
  },
  {
    "count": 25,
    "stem": "arabian",
    "term": "arabian"
  },
  {
    "count": 25,
    "stem": "pathwai",
    "term": "pathway"
  },
  {
    "count": 25,
    "stem": "blank",
    "term": "blank"
  },
  {
    "count": 25,
    "stem": "colin",
    "term": "colin"
  },
  {
    "count": 25,
    "stem": "intercept",
    "term": "intercepted"
  },
  {
    "count": 25,
    "stem": "classroom",
    "term": "classroom"
  },
  {
    "count": 25,
    "stem": "erod",
    "term": "eroding"
  },
  {
    "count": 25,
    "stem": "rancor",
    "term": "rancor"
  },
  {
    "count": 25,
    "stem": "fantasi",
    "term": "fantasy"
  },
  {
    "count": 25,
    "stem": "exert",
    "term": "exert"
  },
  {
    "count": 25,
    "stem": "feud",
    "term": "feud"
  },
  {
    "count": 25,
    "stem": "fatal",
    "term": "fatal"
  },
  {
    "count": 25,
    "stem": "rico",
    "term": "rico"
  },
  {
    "count": 25,
    "stem": "overlap",
    "term": "overlapping"
  },
  {
    "count": 25,
    "stem": "trajectori",
    "term": "trajectory"
  },
  {
    "count": 25,
    "stem": "backyard",
    "term": "backyard"
  },
  {
    "count": 25,
    "stem": "implicitli",
    "term": "implicitly"
  },
  {
    "count": 25,
    "stem": "harper",
    "term": "harper"
  },
  {
    "count": 25,
    "stem": "carol",
    "term": "carol"
  },
  {
    "count": 25,
    "stem": "comei",
    "term": "comey"
  },
  {
    "count": 25,
    "stem": "dot",
    "term": "dot"
  },
  {
    "count": 24,
    "stem": "everydai",
    "term": "everyday"
  },
  {
    "count": 24,
    "stem": "darfur",
    "term": "darfur"
  },
  {
    "count": 24,
    "stem": "unsuccess",
    "term": "unsuccessful"
  },
  {
    "count": 24,
    "stem": "extol",
    "term": "extolled"
  },
  {
    "count": 24,
    "stem": "fring",
    "term": "fringe"
  },
  {
    "count": 24,
    "stem": "silli",
    "term": "silliness"
  },
  {
    "count": 24,
    "stem": "letterman",
    "term": "letterman"
  },
  {
    "count": 24,
    "stem": "colo",
    "term": "colo"
  },
  {
    "count": 24,
    "stem": "enriqu",
    "term": "enrique"
  },
  {
    "count": 24,
    "stem": "turnaround",
    "term": "turnaround"
  },
  {
    "count": 24,
    "stem": "humor",
    "term": "humor"
  },
  {
    "count": 24,
    "stem": "akin",
    "term": "akin"
  },
  {
    "count": 24,
    "stem": "reconcil",
    "term": "reconcile"
  },
  {
    "count": 24,
    "stem": "dave",
    "term": "dave"
  },
  {
    "count": 24,
    "stem": "crist",
    "term": "crist"
  },
  {
    "count": 24,
    "stem": "casino",
    "term": "casino"
  },
  {
    "count": 24,
    "stem": "purpl",
    "term": "purple"
  },
  {
    "count": 24,
    "stem": "competitor",
    "term": "competitors"
  },
  {
    "count": 24,
    "stem": "fiat",
    "term": "fiat"
  },
  {
    "count": 24,
    "stem": "sheldon",
    "term": "sheldon"
  },
  {
    "count": 24,
    "stem": "fame",
    "term": "fame"
  },
  {
    "count": 24,
    "stem": "misl",
    "term": "misled"
  },
  {
    "count": 24,
    "stem": "nurtur",
    "term": "nurture"
  },
  {
    "count": 24,
    "stem": "cleaner",
    "term": "cleaner"
  },
  {
    "count": 24,
    "stem": "hop",
    "term": "hop"
  },
  {
    "count": 24,
    "stem": "forai",
    "term": "foray"
  },
  {
    "count": 24,
    "stem": "emptiv",
    "term": "emptive"
  },
  {
    "count": 24,
    "stem": "rebound",
    "term": "rebound"
  },
  {
    "count": 24,
    "stem": "harass",
    "term": "harassment"
  },
  {
    "count": 24,
    "stem": "feasibl",
    "term": "feasible"
  },
  {
    "count": 24,
    "stem": "ampl",
    "term": "ample"
  },
  {
    "count": 24,
    "stem": "grandfath",
    "term": "grandfather"
  },
  {
    "count": 24,
    "stem": "jeb",
    "term": "jeb"
  },
  {
    "count": 24,
    "stem": "uproar",
    "term": "uproar"
  },
  {
    "count": 24,
    "stem": "liner",
    "term": "liners"
  },
  {
    "count": 24,
    "stem": "decod",
    "term": "decoder"
  },
  {
    "count": 24,
    "stem": "snub",
    "term": "snub"
  },
  {
    "count": 24,
    "stem": "puzzl",
    "term": "puzzled"
  },
  {
    "count": 24,
    "stem": "reignit",
    "term": "reignite"
  },
  {
    "count": 24,
    "stem": "juri",
    "term": "jury"
  },
  {
    "count": 24,
    "stem": "botch",
    "term": "botched"
  },
  {
    "count": 24,
    "stem": "rosen",
    "term": "rosen"
  },
  {
    "count": 24,
    "stem": "cargo",
    "term": "cargo"
  },
  {
    "count": 24,
    "stem": "freshmen",
    "term": "freshmen"
  },
  {
    "count": 24,
    "stem": "automot",
    "term": "automotive"
  },
  {
    "count": 24,
    "stem": "oversaw",
    "term": "oversaw"
  },
  {
    "count": 24,
    "stem": "toughen",
    "term": "toughen"
  },
  {
    "count": 24,
    "stem": "essenc",
    "term": "essence"
  },
  {
    "count": 24,
    "stem": "inflam",
    "term": "inflamed"
  },
  {
    "count": 24,
    "stem": "mitig",
    "term": "mitigate"
  },
  {
    "count": 24,
    "stem": "harshli",
    "term": "harshly"
  },
  {
    "count": 24,
    "stem": "rumsfeld",
    "term": "rumsfeld"
  },
  {
    "count": 24,
    "stem": "bull",
    "term": "bull"
  },
  {
    "count": 24,
    "stem": "imprison",
    "term": "imprisoned"
  },
  {
    "count": 24,
    "stem": "retak",
    "term": "retake"
  },
  {
    "count": 24,
    "stem": "stagecraft",
    "term": "stagecraft"
  },
  {
    "count": 24,
    "stem": "geopolit",
    "term": "geopolitical"
  },
  {
    "count": 24,
    "stem": "shiit",
    "term": "shiite"
  },
  {
    "count": 24,
    "stem": "staunch",
    "term": "staunch"
  },
  {
    "count": 24,
    "stem": "handili",
    "term": "handily"
  },
  {
    "count": 24,
    "stem": "they're",
    "term": "they're"
  },
  {
    "count": 24,
    "stem": "sectarian",
    "term": "sectarian"
  },
  {
    "count": 24,
    "stem": "capitul",
    "term": "capitulation"
  },
  {
    "count": 24,
    "stem": "darrel",
    "term": "darrell"
  },
  {
    "count": 24,
    "stem": "disgrac",
    "term": "disgraceful"
  },
  {
    "count": 24,
    "stem": "insuffici",
    "term": "insufficiently"
  },
  {
    "count": 24,
    "stem": "reclaim",
    "term": "reclaim"
  },
  {
    "count": 24,
    "stem": "cartel",
    "term": "cartels"
  },
  {
    "count": 24,
    "stem": "lieberman",
    "term": "lieberman"
  },
  {
    "count": 24,
    "stem": "dilma",
    "term": "dilma"
  },
  {
    "count": 24,
    "stem": "warhead",
    "term": "warheads"
  },
  {
    "count": 24,
    "stem": "excori",
    "term": "excoriated"
  },
  {
    "count": 24,
    "stem": "heap",
    "term": "heap"
  },
  {
    "count": 24,
    "stem": "mallei",
    "term": "malley"
  },
  {
    "count": 24,
    "stem": "veget",
    "term": "vegetables"
  },
  {
    "count": 24,
    "stem": "alex",
    "term": "alex"
  },
  {
    "count": 24,
    "stem": "unpredict",
    "term": "unpredictable"
  },
  {
    "count": 24,
    "stem": "swath",
    "term": "swath"
  },
  {
    "count": 24,
    "stem": "keynesian",
    "term": "keynesian"
  },
  {
    "count": 24,
    "stem": "healthier",
    "term": "healthier"
  },
  {
    "count": 24,
    "stem": "implement",
    "term": "implementation"
  },
  {
    "count": 24,
    "stem": "administ",
    "term": "administer"
  },
  {
    "count": 24,
    "stem": "ash",
    "term": "ash"
  },
  {
    "count": 24,
    "stem": "degrad",
    "term": "degrading"
  },
  {
    "count": 24,
    "stem": "avid",
    "term": "avid"
  },
  {
    "count": 24,
    "stem": "discretion",
    "term": "discretion"
  },
  {
    "count": 24,
    "stem": "empathi",
    "term": "empathy"
  },
  {
    "count": 24,
    "stem": "we're",
    "term": "we're"
  },
  {
    "count": 24,
    "stem": "rebalanc",
    "term": "rebalancing"
  },
  {
    "count": 24,
    "stem": "scranton",
    "term": "scranton"
  },
  {
    "count": 24,
    "stem": "tourist",
    "term": "tourists"
  },
  {
    "count": 24,
    "stem": "transact",
    "term": "transactions"
  },
  {
    "count": 24,
    "stem": "wheeler",
    "term": "wheeler"
  },
  {
    "count": 23,
    "stem": "landslid",
    "term": "landslide"
  },
  {
    "count": 23,
    "stem": "haunt",
    "term": "haunt"
  },
  {
    "count": 23,
    "stem": "tanzania",
    "term": "tanzania"
  },
  {
    "count": 23,
    "stem": "unrel",
    "term": "unrelenting"
  },
  {
    "count": 23,
    "stem": "mercuri",
    "term": "mercury"
  },
  {
    "count": 23,
    "stem": "humili",
    "term": "humiliation"
  },
  {
    "count": 23,
    "stem": "leahi",
    "term": "leahy"
  },
  {
    "count": 23,
    "stem": "salvador",
    "term": "salvador"
  },
  {
    "count": 23,
    "stem": "onstag",
    "term": "onstage"
  },
  {
    "count": 23,
    "stem": "slain",
    "term": "slain"
  },
  {
    "count": 23,
    "stem": "stewardship",
    "term": "stewardship"
  },
  {
    "count": 23,
    "stem": "decreas",
    "term": "decrease"
  },
  {
    "count": 23,
    "stem": "simon",
    "term": "simon"
  },
  {
    "count": 23,
    "stem": "reactor",
    "term": "reactors"
  },
  {
    "count": 23,
    "stem": "statewid",
    "term": "statewide"
  },
  {
    "count": 23,
    "stem": "softwar",
    "term": "software"
  },
  {
    "count": 23,
    "stem": "cyber",
    "term": "cyber"
  },
  {
    "count": 23,
    "stem": "strickland",
    "term": "strickland"
  },
  {
    "count": 23,
    "stem": "cheerlead",
    "term": "cheerleader"
  },
  {
    "count": 23,
    "stem": "schneiderman",
    "term": "schneiderman"
  },
  {
    "count": 23,
    "stem": "outgo",
    "term": "outgoing"
  },
  {
    "count": 23,
    "stem": "resurg",
    "term": "resurgent"
  },
  {
    "count": 23,
    "stem": "chronicl",
    "term": "chronicled"
  },
  {
    "count": 23,
    "stem": "waterboard",
    "term": "waterboarding"
  },
  {
    "count": 23,
    "stem": "hatch",
    "term": "hatch"
  },
  {
    "count": 23,
    "stem": "getti",
    "term": "getty"
  },
  {
    "count": 23,
    "stem": "fold",
    "term": "fold"
  },
  {
    "count": 23,
    "stem": "refut",
    "term": "refute"
  },
  {
    "count": 23,
    "stem": "outset",
    "term": "outset"
  },
  {
    "count": 23,
    "stem": "weinstein",
    "term": "weinstein"
  },
  {
    "count": 23,
    "stem": "fema",
    "term": "fema"
  },
  {
    "count": 23,
    "stem": "orchestr",
    "term": "orchestrated"
  },
  {
    "count": 23,
    "stem": "furlough",
    "term": "furloughs"
  },
  {
    "count": 23,
    "stem": "pragmatist",
    "term": "pragmatist"
  },
  {
    "count": 23,
    "stem": "destin",
    "term": "destinations"
  },
  {
    "count": 23,
    "stem": "furi",
    "term": "fury"
  },
  {
    "count": 23,
    "stem": "slack",
    "term": "slack"
  },
  {
    "count": 23,
    "stem": "fran",
    "term": "fran"
  },
  {
    "count": 23,
    "stem": "feinstein",
    "term": "feinstein"
  },
  {
    "count": 23,
    "stem": "denial",
    "term": "denial"
  },
  {
    "count": 23,
    "stem": "checker",
    "term": "checkers"
  },
  {
    "count": 23,
    "stem": "roar",
    "term": "roaring"
  },
  {
    "count": 23,
    "stem": "strident",
    "term": "strident"
  },
  {
    "count": 23,
    "stem": "proposit",
    "term": "proposition"
  },
  {
    "count": 23,
    "stem": "calder",
    "term": "calder"
  },
  {
    "count": 23,
    "stem": "koh",
    "term": "koh"
  },
  {
    "count": 23,
    "stem": "anew",
    "term": "anew"
  },
  {
    "count": 23,
    "stem": "emul",
    "term": "emulate"
  },
  {
    "count": 23,
    "stem": "barri",
    "term": "barry"
  },
  {
    "count": 23,
    "stem": "gillard",
    "term": "gillard"
  },
  {
    "count": 23,
    "stem": "marvel",
    "term": "marveled"
  },
  {
    "count": 23,
    "stem": "sharper",
    "term": "sharper"
  },
  {
    "count": 23,
    "stem": "upend",
    "term": "upended"
  },
  {
    "count": 23,
    "stem": "longest",
    "term": "longest"
  },
  {
    "count": 23,
    "stem": "censu",
    "term": "census"
  },
  {
    "count": 23,
    "stem": "disillus",
    "term": "disillusioned"
  },
  {
    "count": 23,
    "stem": "wreath",
    "term": "wreath"
  },
  {
    "count": 23,
    "stem": "jpmorgan",
    "term": "jpmorgan"
  },
  {
    "count": 23,
    "stem": "lambast",
    "term": "lambasted"
  },
  {
    "count": 23,
    "stem": "seller",
    "term": "seller"
  },
  {
    "count": 23,
    "stem": "absurd",
    "term": "absurd"
  },
  {
    "count": 23,
    "stem": "blown",
    "term": "blown"
  },
  {
    "count": 23,
    "stem": "turbin",
    "term": "turbine"
  },
  {
    "count": 23,
    "stem": "invad",
    "term": "invaded"
  },
  {
    "count": 23,
    "stem": "swirl",
    "term": "swirl"
  },
  {
    "count": 23,
    "stem": "quell",
    "term": "quell"
  },
  {
    "count": 23,
    "stem": "impromptu",
    "term": "impromptu"
  },
  {
    "count": 23,
    "stem": "cori",
    "term": "cory"
  },
  {
    "count": 23,
    "stem": "citigroup",
    "term": "citigroup"
  },
  {
    "count": 23,
    "stem": "elus",
    "term": "elusive"
  },
  {
    "count": 23,
    "stem": "jeremi",
    "term": "jeremy"
  },
  {
    "count": 23,
    "stem": "unman",
    "term": "unmanned"
  },
  {
    "count": 23,
    "stem": "memor",
    "term": "memorable"
  },
  {
    "count": 23,
    "stem": "cop",
    "term": "cops"
  },
  {
    "count": 23,
    "stem": "philippin",
    "term": "philippines"
  },
  {
    "count": 23,
    "stem": "counterweight",
    "term": "counterweight"
  },
  {
    "count": 23,
    "stem": "cheat",
    "term": "cheat"
  },
  {
    "count": 23,
    "stem": "aviv",
    "term": "aviv"
  },
  {
    "count": 23,
    "stem": "haiti",
    "term": "haiti"
  },
  {
    "count": 23,
    "stem": "staffer",
    "term": "staffers"
  },
  {
    "count": 23,
    "stem": "charit",
    "term": "charitable"
  },
  {
    "count": 23,
    "stem": "misguid",
    "term": "misguided"
  },
  {
    "count": 23,
    "stem": "sec",
    "term": "sec"
  },
  {
    "count": 23,
    "stem": "newcom",
    "term": "newcomer"
  },
  {
    "count": 23,
    "stem": "verg",
    "term": "verge"
  },
  {
    "count": 23,
    "stem": "sullivan",
    "term": "sullivan"
  },
  {
    "count": 23,
    "stem": "fond",
    "term": "fond"
  },
  {
    "count": 23,
    "stem": "consumpt",
    "term": "consumption"
  },
  {
    "count": 23,
    "stem": "vindic",
    "term": "vindication"
  },
  {
    "count": 23,
    "stem": "claus",
    "term": "clause"
  },
  {
    "count": 23,
    "stem": "terrif",
    "term": "terrific"
  },
  {
    "count": 23,
    "stem": "unannounc",
    "term": "unannounced"
  },
  {
    "count": 23,
    "stem": "graphic",
    "term": "graphic"
  },
  {
    "count": 23,
    "stem": "renounc",
    "term": "renounce"
  },
  {
    "count": 23,
    "stem": "metaphor",
    "term": "metaphor"
  },
  {
    "count": 23,
    "stem": "garner",
    "term": "garnered"
  },
  {
    "count": 23,
    "stem": "liken",
    "term": "likened"
  },
  {
    "count": 23,
    "stem": "clark",
    "term": "clark"
  },
  {
    "count": 23,
    "stem": "overrid",
    "term": "override"
  },
  {
    "count": 23,
    "stem": "punit",
    "term": "punitive"
  },
  {
    "count": 23,
    "stem": "preoccupi",
    "term": "preoccupied"
  },
  {
    "count": 23,
    "stem": "victoria",
    "term": "victoria"
  },
  {
    "count": 23,
    "stem": "resumpt",
    "term": "resumption"
  },
  {
    "count": 22,
    "stem": "warner",
    "term": "warner"
  },
  {
    "count": 22,
    "stem": "disrespect",
    "term": "disrespect"
  },
  {
    "count": 22,
    "stem": "dug",
    "term": "dug"
  },
  {
    "count": 22,
    "stem": "underdog",
    "term": "underdog"
  },
  {
    "count": 22,
    "stem": "pell",
    "term": "pell"
  },
  {
    "count": 22,
    "stem": "chastis",
    "term": "chastise"
  },
  {
    "count": 22,
    "stem": "libertarian",
    "term": "libertarian"
  },
  {
    "count": 22,
    "stem": "cutback",
    "term": "cutbacks"
  },
  {
    "count": 22,
    "stem": "tailor",
    "term": "tailored"
  },
  {
    "count": 22,
    "stem": "refocu",
    "term": "refocus"
  },
  {
    "count": 22,
    "stem": "priebu",
    "term": "priebus"
  },
  {
    "count": 22,
    "stem": "jefferson",
    "term": "jefferson"
  },
  {
    "count": 22,
    "stem": "salvag",
    "term": "salvage"
  },
  {
    "count": 22,
    "stem": "swell",
    "term": "swelling"
  },
  {
    "count": 22,
    "stem": "savvi",
    "term": "savvy"
  },
  {
    "count": 22,
    "stem": "unspecifi",
    "term": "unspecified"
  }
]
```


##Write Back API

This call allows users to push data into the Postgresql database.

###api/v2/stories/custom_tags (PUT)

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

Set custom_story_tags on the story with stories_id 1000 to 'foo' and 'bar'

curl -X PUT -d stories_id=10000 -d custom_tag=foo -d custom_tag=bar http://mediacloud.org/api/v2/stories/custom_tags


###api/v2/story_sentences/custom_tags (PUT)

URL                                                                       Function
---------------------------------      --------------------------------------------------
api/v2/story_sentences/custom_tags                    Add custom tags to a story sentence. Must be a PUT request
---------------------------------      --------------------------------------------------

####Query Parameters 

--------------------------------------------------------------------------------------------------------
Parameter                     Notes
---------------------------   --------------------------------------------------------------------------
 story_sentences_id            The id of the story sentence to which to add the custom tags

 custom_tag                    Can be specified multiple times to add multiple tags to the story sentence
--------------------------------------------------------------------------------------------------------

####Example

Set the custom_sentence_tags on the story sentence with story_sentences_id 1000 to 'foo' and 'bar'

curl -X PUT -d stories_id=10000 -d custom_tag=foo -d custom_tag=bar http://mediacloud.org/api/v2/story_sentences/custom_tags


#Extended Examples

## Output Format / JSON
  
The format of the API responses is determined by the ‘Accept’ header on the request. The default is ‘application/json’. Other supported formats include 'text/html', 'text/x-json', and  'text/x-php-serialization'. It’s recommended that you explicitly set the ‘Accept’ header rather than relying on the default.
 
Here’s an example of setting the ‘Accept’ header in Python

```python  
import pkg_resources  

import requests   
assert pkg_resources.get_distribution("requests").version >= '1.2.3'
 
r = requests.get( 'http://mediacloud.org/api/stories/all_processed?last_processed_stories_id=1', auth=('mediacloud-admin', KEY), headers = { 'Accept': 'application/json'})  

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

Since the subset is now processed we can obtain all of its stories by repeatedly querying list_subset_processed and changing the last_processed_stories_id parameter. 
This is shown in the Python code below where process_stories is a user provided function to process this data.

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

##Grab all stories in the New York Times during October 2012

###Find the media_id of the New York Times

Currently, the best way to do this is to create a CSV file with all media sources as shown in the earlier example.

Once you have this CSV file, manually search for the New York Times. You should find an entry for the New York Times at the top of the file with media_id 1.

###Create a subset
curl -X PUT -d start_date=2012-10-01 -d end_date=2012-11-01 -d media_id=1 http://mediacloud.org/api/v2/stories/subset

Save the story_subsets_id

###Wait until the subset is ready

See the 25 msm example above.

###Grab stories from the processed stream

See the 25 msm example above.

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
Below q is set to "sentence:trayvon" and fq is set to "media_sets_id:7125" and  "publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]". (Note that ":", "[", and "]" are URL encoded.)

curl 'http://mediacloud.org/api/v2/solr/wc?q=sentence%3Atrayvon&fq=media_sets_id%3A7125&fq=publish_date%3A%5B2012-04-01T00%3A00%3A00.000Z+TO+2013-05-01T00%3A00%3A00.000Z%5D'

Alternatively, we could use a single large query by setting q to "sentence:trayvon AND media_sets_id:7125 AND publish_date:[2012-04-01T00:00:00.000Z TO 2013-05-01T00:00:00.000Z]". 

curl 'http://mediacloud.org/api/v2/solr/wc?q=sentence%3Atrayvon+AND+media_sets_id%3A7125+AND+publish_date%3A%5B2012-04-01T00%3A00%3A00.000Z+TO+2013-05-01T00%3A00%3A00.000Z%5D&fq=media_sets_id%3A7135&fq=publish_date%3A%5B2012-04-01T00%3A00%3A00.000Z+TO+2013-05-01T00%3A00%3A00.000Z%5D'

##Tag sentences in a story based on whether they have an odd or even number of characters

For simplicity, we assume that the user is interested in the story with stories_id 100

```python

stories_id = 100
r = requests.get( 'http://mediacloud.org/api/v2/story/single/' + stories_id, headers = { 'Accept': 'application/json'} )
data = r.json()
story = data[0]

for story_sentence in story['story_sentences']:
    sentence_length = len( story_sentence['sentence'] )
    story_sentences_id = story_sentence[ 'story_sentences_id' ]

    custom_tags = set(story_sentence[ 'custom_tags' ])

    if sentence_length %2 == 0:
       custom_tags.append( 'odd' )
    else:
       custom_tags.append( 'even' )

    r = requests.put( 'http://mediacloud.org/api/v2/story_sentences/custom_tags/' + stories_id, { 'custom_tags': custom_tags}, headers = { 'Accept': 'application/json'} )  

```

##Get word counts for top words for sentences matching with the custom sentence tag 'odd'

###Make a request for the word counts based on the custom sentence tag 'odd'

Below q is set to "custom_sentence_tag:odd". (Note that ":", "[", and "]" are URL encoded.)

curl 'http://mediacloud.org/api/v2/solr/wc?q=custom_sentence_tag%3Afoobar'

##Grab stories from 10 January 2014 with the custom tag 'foobar'

###Create a subset
curl -X PUT -d start_date=2014-01-10 -d end_date=2014-01-11 -d custom_story_tag=foobar http://mediacloud.org/api/v2/stories/subset

Save the story_subsets_id

###Wait until the subset is ready

See the 25 msm example above.

###Grab stories from the processed stream

See the 25 msm example above.
