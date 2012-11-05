<?php
$t0 = microtime();  // do some performance monitoring, old school
// initialization
require_once('./lib/CouchSimple.php');
$options = parse_ini_file("config.ini");
$couch = new CouchSimple($options);

$t1 = microtime();
// update cached list of (two-part) domain names
$updatedDomainCache = false;
define('CACHED_DOMAIN_LIST', 'cache/'.$options['host'].'_domain_two_part.json');
if(!file_exists(CACHED_DOMAIN_LIST) || (microtime()-filemtime(CACHED_DOMAIN_LIST))>(24*60*60) ){
  $domainListJson = $couch->send("GET", "/mediacloud/_design/examples/_view/domain_two_part?group=true");
  file_put_contents(CACHED_DOMAIN_LIST,$domainListJson);
  $updatedDomainCache = true;
}
// load from cached file
$domainTwoPart = json_decode(file_get_contents(CACHED_DOMAIN_LIST));
$domainList = array();
foreach( $domainTwoPart->rows as $row ) {
  array_push($domainList, $row->key);
}
sort($domainList);
$t2 = microtime();
?>

<!DOCTYPE html>
<html>
  <head>
    <title>MediaCloud API Client Examples</title>
    <link href="css/mediacloud.css" rel="stylesheet" type="text/css"/>
    <link href="css/bootstrap.min.css" rel="stylesheet" type="text/css"/>
    <script type="text/javascript" src="js/jquery-1.8.2.min.js"></script>
    <script type="text/javascript" src="js/bootstrap.min.js"></script>
    <script type="text/javascript" src="js/d3.v2.min.js"></script>
  </head>

  <body>

<div class="container"> 


  <div class="row">
    <div class="span12">
      <div class="page-header">
        <h1>MediaCloud API Client <small>Examples</small></h1>
      </div>
    </div>
  </div>


<?php
// max story id
$results = json_decode( $couch->send("GET", "/mediacloud/_design/examples/_view/max_story_id") ); 
$maxStoryId = $results->rows[0]->value;
$t3 = microtime();

// total story count
$results = json_decode( $couch->send("GET", "/mediacloud/_design/examples/_view/total_stories") ); 
$storyCount = $results->rows[0]->value;
$t4 = microtime();

// english story count
$englishStoryCount = null;
$results = json_decode( $couch->send("GET", "/mediacloud/_design/examples/_view/is_english?group=true") ); 
foreach ($results->rows as $row){
  if($row->key==true) {
    $englishStoryCount = $row->value;
  }
}
$t5 = microtime();

?>

  <div class="row">
    <div class="span12">

<?php
if($updatedDomainCache){
?>
  <div class="alert alert-info">
    <button type="button" class="close" data-dismiss="alert"></button> 
    <strong>FYI:</strong> just updated the cached list of domains
  </div>
<?php
}
?>

      <p><i>
      <?=$storyCount?> stories in the database (<?=round(100*$englishStoryCount/$storyCount)?>% in english). The max story id is <?=$maxStoryId?>.
      </i></p>
    </div>
  </div>

  <div class="row">

    <div class="span6" id="mcWordCounts">
      <h3>Story Length</h3>
      <p>
      Here is a histogram of story length.  The horizontal axis is word length (0-200, 200-400, etc). 
      The vertical axis is the number of stories that have that many words.  
      </p>
          <!-- chart will be filled in by ajax call -->
    </div>

     <div class="span6" id="mcReadability">
      <h3>Story Reading Level</h3>
      <p>
      Here is a histogram of story reading grade level.  The horizontal axis is grade level 
      the story is written at. The vertical axis is the number of stories scored at that grade level. 
      </p>
          <!-- chart will be filled in by ajax call -->
    </div>
  </div>


  <div class="row">
    <div class="span12">
      <hr/>
    </div>
  </div>

  
  <div class="row">
    <div class="span12">
      <h2>Filter For <input type="text" data-provide="typeahead" id="mcPickDomain" placeholder="somenews.com"></h2>
    </div>
    <div id="mcFilteredResults" style="display:none">
      <div class="span12">
        <p id="mcFilteredInfo">
        </p>
      </div>
      <div class="span6">
        <h3>Word Count</h3>
        <div id="mcFilteredWordCounts">
          <!-- chart will be filled in by ajax call -->
        </div>
      </div>
      <div class="span6">
        <h3>Reading Level</h3>
        <div id="mcFilteredReadability">
          <!-- chart will be filled in by ajax call -->
        </div>
      </div>
    </div>
  </div>


  <div class="row">
    <div class="span12">
      <hr/>
    </div>
  </div>
  

  <div class="row">
    <div class="span12">
      <p><b>Top Sources:</b>
<?php
// sources
function compareRowValue($a,$b){ return $b->value > $a->value; }
uasort($domainTwoPart->rows,'compareRowValue');
$topTwentydomainList = array_slice($domainTwoPart->rows, 0,20);
foreach($topTwentydomainList as $row){
?>  <a href="http://<?=$row->key?>"><?=$row->key?></a> <span class="badge"><?=$row->value?></span>
<?php
}
$t6 = microtime();
?>
      </p>
    </div>
  </div >

</div>

<script type="text/javascript">
// called by returned JS
function updateFilteredInfo(domain, storyCount){
  $('#mcFilteredInfo').html("We know about "+storyCount+" articles from "+domain);
}
// called by returned JS
function updateFilterResults(domain){
  $('#mcFilteredResults').hide();
  $('#mcFilteredInfo').empty();
  $('#mcFilteredWordCounts').empty();
  $('#mcFilteredReadability').empty();
  $.ajax({
    type: "GET",
    url:"data.js.php?domain="+domain,
    dataType: 'script'
  });
}
// fire ajax request when user filters by news source
$('#mcPickDomain').typeahead({
    source: <?= json_encode($domainList) ?>,
    updater: function(item){
        updateFilterResults(item);
    }
});
</script>

<script type="text/javascript">

// helper function to draw a standard histogram chart
function histogramChart(container, dataset, chartWidth, chartHeight, barWidth, maxXValue,barsToShow, maxY, xTickCount) {
  var y = d3.scale.linear()
       .domain([0, maxY])
       .range([0, chartHeight]);
  var x = d3.scale.linear()
       .domain([0,maxXValue])
       .range([0, chartWidth]);
  var chart = d3.select(container).append("svg")
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
       .data(x.ticks(xTickCount))
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
}

// load up the aggregate charts
$(function(){
  $.ajax({
      type: "GET",
      url:"data.js.php",
      dataType: 'script'
    });
});

</script>

<!--
<?php
// print out performance of each section
print "1: ".round($t1-$t0,4)."<br/>";
print "2: ".round($t2-$t1,4)."<br/>";
print "3: ".round($t3-$t2,4)."<br/>";
print "4: ".round($t4-$t3,4)."<br/>";
print "5: ".round($t5-$t4,4)."<br/>";
print "6: ".round($t6-$t5,4)."<br/>";
?>
-->

  </body>

</html>
