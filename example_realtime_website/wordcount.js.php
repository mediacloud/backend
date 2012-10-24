<?php
// initialization
require_once('./lib/CouchSimple.php');
$options = parse_ini_file("config.ini");
$couch = new CouchSimple($options);

// parse args
$domain = null;
if(array_key_exists('domain',$_GET)) $domain = $_GET['domain'];

// get data (word count by length of story)
$wcBarsToShow = 20;
$wcBucketSize = 200;  // must match view
$wcMaxStoryLengthToShow = ($wcBarsToShow)*$wcBucketSize;

if($domain==null){
  $queryUrl = "/mediacloud/_design/examples/_view/word_counts?group=true&startkey=0&keyend=".$wcMaxStoryLengthToShow;
} else {
  $queryUrl = "/mediacloud/_design/examples/_view/source_word_counts?group=true&".
              "startkey=\"".$domain."_0\"&".
              "endkey=\"".$domain."_".$wcMaxStoryLengthToShow."\"";
}

$results = json_decode( $couch->send("GET", $queryUrl) ); 
$wcResults = array();
$i = 0;   // prefill array
for($i=0;$i<$wcBarsToShow;$i++){
  $wcResults[$i*$wcBucketSize] = 0;
}
$wcMaxIncludedStoryCount = 0;
foreach ($results->rows as $row){
  if($domain) {
    $key = str_replace($domain."_","",$row->key);
  } else {
    $key = $row->key;
  }
  if (array_key_exists($key,$wcResults)) {
    $wcResults[$key] = $row->value;
    $wcMaxIncludedStoryCount = max($wcMaxIncludedStoryCount,$row->value);
  }
}
?>
var dataset = [<?php
foreach ($wcResults as $wordCount=>$storyCount){
?> <?=$storyCount?>,<?php }?> ];
histogramChart("#mcFilteredWordCounts",dataset,400,100,20,<?=$wcMaxStoryLengthToShow?>,<?=$wcBarsToShow?>, <?=$wcMaxIncludedStoryCount?>,<?=$wcBarsToShow/4?>);
$('#mcFilteredResults').show();