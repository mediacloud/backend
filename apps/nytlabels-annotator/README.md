# NYTLabels annotator

Requires at least 1 GB of RAM.


## Annotating arbitrary text

Start the annotator:

```bash
docker run -it -p 8080:8080 gcr.io/mcback/nytlabels-annotator:latest
```

create a file with text to annotate:

```bash
# https://globalvoices.org/2021/01/10/a-digital-artist-depicts-the-lives-of-thais-and-the-struggle-for-democracy/
cat << EOF > test.txt
A digital artist depicts the lives of Thais and the struggle for democracy

Global Voices interviews artist Pssyppl about protest art and the prospects for the democracy movement

Many artists supported the youth-led protest movement that demanded democratic reforms in Thailand in 2020. One of these artists is Pssyppl, described by BK Magazine as a “fast-emerging artist and designer, who produces dark, largely satirical digital paintings that reflect the burning issues of our time.”

In an article featuring him and other artists in BK Magazine, Pssyppl shared this description of his artistic vision:

My digital artwork focuses on events that are happening around me—events that leave me with a certain feeling inside my head, and then that feeling is molded and visualized in a sarcastic way through digital paintings. The reason I did these pieces is because of anger—anger that I cannot say anything or do anything to resist this corrupt system [that rules Thailand]. Art is my only way to express this smoldering emotion inside my mind.

Anger does indeed appear to be a key driving force behind the digital artworks Pssyppl publishes on Instagram. One of them depicts Thais’ resistance against a government that uses the repressive Section 112 law to arrest those who criticize the monarchy.

This artwork was featured by news website New Naratif and includes a description from the artist:

We the people have been oppressed, manipulated and controlled by higher powers for as long as I remember. Now that their ivory tower has started to tremble, it’s time for us to rise up for a better future not just for ourselves, but also for the generations to come.

Another artwork criticizes the military, which staged a coup in 2014 and continues to dominate the civilian government despite the holding of elections in 2019.

I symbolised this rotten system of Thailand into the character of a general. The system that barks order at you and you will follow. The system that tells you from the other side of the poster that you already have a good life, don’t ask questions, don’t try to change the way things are. The system that hides all those bodies of the people that try to fight for their life, distorting history and turns people against each other. In the end, this is just a poster. You either choose to believe in the ‘system’ that is trying to control you through the artwork, or together, we can fight the system and tear it down to the ground.

I interviewed Pssyppl via Twitter about the importance of art in sustaining the pro-democracy protest movement in Thailand:

In my opinion, in the country where people cannot speak out the fact and spread out the truth, art, music, performance and any other form of expression other than words are quite important. They are the alternative ways for people to express their feelings, to make people listen.

I also asked him about the prospect of the campaign for democracy in 2021:

We have come a long way since the coup seven years ago. The fight is going to be long and it might last longer than 2021 in my opinion. I can’t really tell what the future would hold, but changes are coming and the glimpse of hope is starting to surface. Now that there’s covid-19 around, we have more responsibility than before. It is going to be a slow process but I believe that we surely are progressing.

This is his message to fellow artists:

To me, it’s of utmost importance that you never doubt yourself. There’s gonna be the work you hate, you are gonna feel tired and confused whether you’ve chosen the right part. But if it’s what you love, never stop do art. If you fail, try and fail again until you fall in love with your failure.
EOF
```

and then `POST` said file as JSON to the annotator:

```bash
echo '{}' | \
  jq --arg key0 text --arg value0 "$(cat test.txt)" '. | .[$key0]=$value0' | \
  curl --verbose --silent --trace-time --header "Content-Type: application/json" -X POST --data-binary @- http://127.0.0.1:8080/predict.json | \
  jq ".descriptors600"
```

Alternatively, to try out just the `descriptors600` model:

```bash
echo '{"models": ["descriptors600"]}' | \
  jq --arg key0 text --arg value0 "$(cat test.txt)" '. | .[$key0]=$value0' | \
  curl --verbose --silent --trace-time --header "Content-Type: application/json" -X POST --data-binary @- http://127.0.0.1:8080/predict.json
```
