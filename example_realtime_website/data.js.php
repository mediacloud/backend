<?php
// initialization
require_once('./lib/CouchSimple.php');
$options = parse_ini_file("config.ini");
$couch = new CouchSimple($options);

// parse args
$domain = null;
if(array_key_exists('domain',$_GET)) $domain = $_GET['domain'];
?>


<?php
/****************************************************************************************/
/** MetaData ** /
/****************************************************************************************/

if($domain==null){
  $queryUrl = "/mediacloud/_design/examples/_view/total_stories";
  $destDivWc = "mcWordCounts";
  $destDivRl = "mcReadability";
} else {
  $queryUrl = "/mediacloud/_design/examples/_view/source_story_counts?group=true&key=\"".$domain."\"";
  $destDivWc = "mcFilteredWordCounts";
  $destDivRl = "mcFilteredReadability";
}
$results = json_decode( $couch->send("GET", $queryUrl) ); 
$storyCount = $results->rows[0]->value;

if($domain!=null){
?>
  updateFilteredInfo("<?=$domain?>",<?=$storyCount?>);
<?php
}
?>

<?php
/****************************************************************************************/
/** Word Counts ** /
/****************************************************************************************/

// get data (word count by length of story)
$wcBarsToShow = 20;
$wcBucketSize = 200;  // must match view
$wcMaxStoryLengthToShow = ($wcBarsToShow)*$wcBucketSize;

if($domain==null){
  $queryUrl = "/mediacloud/_design/examples/_view/word_counts?group=true&startkey=0&endkey=".$wcMaxStoryLengthToShow;
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
// word count info
var wcDataset = [<?=implode(",",$wcResults); ?>];
histogramChart("#<?=$destDivWc?>",wcDataset,400,100,20,<?=$wcMaxStoryLengthToShow?>,<?=$wcBarsToShow?>, <?=$wcMaxIncludedStoryCount?>,<?=$wcBarsToShow/4?>);


<?php 
/****************************************************************************************/
/** Readability ** /
/****************************************************************************************/
$rlBarsToShow = 20;
if($domain==null){
  $queryUrl = "/mediacloud/_design/examples/_view/reading_grade_counts?group=true&startkey=0&endkey=".$rlBarsToShow;
} else {
  $queryUrl = "/mediacloud/_design/examples/_view/source_reading_grade_counts?group=true&".
              "startkey=\"".$domain."_0\"&".
              "endkey=\"".$domain."_".$rlBarsToShow."\"";
}
$results = json_decode( $couch->send("GET", $queryUrl) ); 
$rlResults = array();
$i = 0;   // prefill array
$rlMaxIncludedStoryCount = 0;
$rlMaxReadingLevelToShow = 20;
for($i=0;$i<$rlMaxReadingLevelToShow;$i++) {  // prefill array
  $rlResults[$i] = 0;
}
foreach ($results->rows as $row){
  if($domain) {
    $key = str_replace($domain."_","",$row->key);
    $key = intval($key);
  } else {
    $key = $row->key;
  }
  if (array_key_exists($key,$rlResults)) {
    $rlResults[$key] = $row->value;
    $rlMaxIncludedStoryCount = max($rlMaxIncludedStoryCount,$row->value);
  }
}

?>
// readability info
var rlDataset = [<?=implode(",",$rlResults); ?>];
histogramChart("#<?=$destDivRl?>",rlDataset,400,50,20,<?=$rlMaxReadingLevelToShow?>,<?=$rlBarsToShow?>, <?=$rlMaxIncludedStoryCount?>,10);


<?php 
/****************************************************************************************/
/** Cleanup ** /
/****************************************************************************************/

if($domain!=null){
?>
  // show results
  $('#mcFilteredResults').show();
<?php
}
?>