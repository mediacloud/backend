<?php
// initialization
require_once('./lib/CouchSimple.php');
$options = parse_ini_file("config.ini");
$couch = new CouchSimple($options);

// parse args
$domain = null;
if(array_key_exists('domain',$_GET)) $domain = $_GET['domain'];

// get data (word count by length of story)
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
  } else {
    $key = $row->key;
  }
  if (array_key_exists($key,$rlResults)) {
    $rlResults[$key] = $row->value;
    $rlMaxIncludedStoryCount = max($rlMaxIncludedStoryCount,$row->value);
  }
}
?>
var dataset = [<?php
foreach ($rlResults as $wordCount=>$storyCount){
?> <?=$storyCount?>,<?php }?> ];
histogramChart("#mcFilteredReadability",dataset,400,50,20,<?=$rlMaxReadingLevelToShow?>,<?=$rlBarsToShow?>, <?=$rlMaxIncludedStoryCount?>,10);
$('#mcFilteredResults').show();