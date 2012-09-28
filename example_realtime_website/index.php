<!DOCTYPE html>
<html>
  <head>
    <title>MediaCloud API Client Examples</title>
    <link href="css/mediacloud.css" rel="stylesheet" type="text/css"/>
    <link href="css/bootstrap.min.css" rel="stylesheet" type="text/css"/>
    <script type="text/javascript" src="js/d3.v2.min.js"></script>
  </head>

  <body>

<?php
require_once('./lib/CouchSimple.php');

$options['host'] = "localhost"; 
$options['port'] = 5984;

$couch = new CouchSimple($options);

// total article count
$results = json_decode( $couch->send("GET", "/mediacloud/_design/examples/_view/max_story_id") ); 
$maxStoryId = $results->rows[0]->value;

// total article count
$results = json_decode( $couch->send("GET", "/mediacloud/_design/examples/_view/total_articles") ); 
$articleCount = $results->rows[0]->value;

// article count by length
$results = json_decode( $couch->send("GET", "/mediacloud/_design/examples/_view/word_counts?group=true") ); 

$wordCounts = array();
$barsToShow = 40;
$bucketSize = 200;  // must match view
$maxStoryLengthToShow = ($barsToShow)*$bucketSize;
$includedStories = 0;
$excludedStories = 0;
// prefill array
$i = 0;
for($i=0;$i<$barsToShow;$i++){
  $wordCounts[$i*$bucketSize] = 0;
}
// 
$maxIncludedStoryCount = 0;
foreach ($results->rows as $row){
  if (array_key_exists($row->key,$wordCounts)) {
    $wordCounts[$row->key] = $row->value;
    $maxIncludedStoryCount = max($maxIncludedStoryCount,$row->value);
    $includedStories+=$row->value;
  } else {
    $excludedStories+=$row->value;
  }
}

$includedStoriesPct = $includedStories/($includedStories+$excludedStories);
?>

<div class="container"> 
  <div class="row">
    <div class="span12">
      <div class="page-header">
        <h1>MediaCloud API Client <small>Examples</small></h1>
      </div>
      <div class="well">
      <?=$articleCount?> stories in the database. The max story id is <?=$maxStoryId?>.
      </div>
    </div>
    <div class="span12" id="mcStoryLength">
      <h2>Story Length</h2>
      <p>
      Here is a histogram of story length.  The horizontal axis is word length (0-200, 200-400, etc). 
      The vertical axis is the number of stories that have that many words.  This graph includes 
      <?=round($includedStoriesPct*100)?>% of the stories (excluding the
      <?=$excludedStories?> stories longer than <?=$maxStoryLengthToShow?> words).
      </p>
    </div>
  </div>
</div>

<script type="text/javascript">
var datasetKeys = [
<?php
foreach ($wordCounts as $wordCount=>$storyCount){
?> <?=$wordCount?>,
<?php
}
?>
]
var dataset = [
<?php
foreach ($wordCounts as $wordCount=>$storyCount){
?> <?=$storyCount?>,
<?php
}
?>
];
</script>

<script type="text/javascript">
var chartHeight = 200;
var chartWidth = 800;
var barWidth = 20;
var maxStoryLenth = <?=$maxStoryLengthToShow?>;
var barsToShow = <?=$barsToShow?>;
var maxIncludedStoryCount = <?=$maxIncludedStoryCount?>;
var y = d3.scale.linear()
     .domain([0, maxIncludedStoryCount])
     .range([0, chartHeight]);
var x = d3.scale.linear()
     .domain([0,maxStoryLenth])
     .range([0, chartWidth]);
var chart = d3.select("#mcStoryLength").append("svg")
     .attr("class", "chart")
     .attr("width", barWidth*barsToShow+50)
     .attr("height", chartHeight+25)
     .append("g")
     .attr("transform", "translate(10,0)");
chart.selectAll("rect")
     .data(dataset)
     .enter().append("rect")
     .attr("x", function(d,i) { return i*barWidth; })
     .attr("y", function(d) {return chartHeight - y(d);} )
     .attr("height", y)
     .attr("width", barWidth);
chart.selectAll(".rule")
     .data(x.ticks(barsToShow/4))
     .enter().append("text")
     .attr("class", "rule")
     .attr("x", x)
     .attr("y", chartHeight)
     .attr("dy", 15)
     .attr("text-anchor", "middle")
     .text(String);
chart.append("line")
     .attr("x1", 0)
     .attr("x2", chartWidth)
     .attr("y1", chartHeight)
     .attr("y2", chartHeight)
     .style("stroke", "#666");
</script>

  </body>

</html>
