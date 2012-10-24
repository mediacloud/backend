<?php
// Returns a list of all the domains in json format (sorted alphabetically)

// initialization
require_once('./lib/CouchSimple.php');
$options = parse_ini_file("config.ini");
$couch = new CouchSimple($options);

// query for list of two-part domains
$results = json_decode( $couch->send("GET", "/mediacloud/_design/examples/_view/domain_two_part?group=true") ); 
$domains = array();
foreach( $results->rows as $row ) {
  array_push($domains, $row->key);
}
sort($domains);

header('Cache-Control: no-cache, must-revalidate');
header('Content-type: application/json');
print json_encode(array("options"=>$domains));
?>
