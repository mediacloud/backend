<?
/*
Plugin Name: Media Cloud Visualizations
Plugin URI: http://mediacloud.org/NO_PAGE_YET
Description: Add functions for outputting MC visualizations.
Version: The Plugin's Version Number, e.g.: 1.0
Author: Steve Schultze
Author URI: http://cyber.law.harvard.edu
*/

add_filter('the_content', 'insert_mcviz_form');
add_filter('the_content_rss', 'insert_mcviz_form');

add_filter('the_content', 'insert_mcviz_results');
add_filter('the_content_rss', 'insert_mcviz_results');

function check_viz_type($viz_type) {
    if ($_REQUEST[viz_type] == $viz_type) {
        return ' checked="checked" ';
    } else {
        return "";
    }
}


function insert_mcviz_form($content) {

    $replace_tag = "mcvizform";
    $content .= '<!-- I ran! -->';
    if (! preg_match("/mcvizform/", $content)) {
        return $content;
    }

    if (($_REQUEST[chart_is_log] == '') || !isset($_REQUEST[chart_is_log])) {
        $_REQUEST[chart_is_log] = 'true';
    }

    if (($_REQUEST[viz_type] == '') || !isset($_REQUEST[viz_type])) {
        $_REQUEST[viz_type] = 'top10';
    } else {
        $content .= $viz_link_comment_javascript;
    }

    // this is used by scriptaculo.us autocompleter
    $viz_form .= '<div class="autocomplete" id="media_list" style="display:none;"></div>';

    $viz_form .= '
		<form  name="mcvizform" id="mcvizform" method="get" action="' .
        get_bloginfo('home') . '" onsubmit=\'mc_check_media_name_and_fill_media_id_allfields(mediaList,"media_source","media_id");\'><input type="hidden" name="page_id" value="5" /><input type="hidden" name="tagset" value="13" /><input type="hidden" name="chart_is_log" value="true" />';

    $viz_form .= '<div style="float:left; width:40%; padding:10px;">';

    $viz_form .= '<b>Step 1: Choose Chart Type</b><br /><br />';

    $viz_form .= '<input name="viz_type" size="40" type="radio" value="top10" ' . check_viz_type("top10") . '/> <b>Top 10:</b> Show the top 10 most mentioned terms for each media source.<br clear="all"><br />';
    $viz_form .= '<input name="viz_type" size="40" type="radio" value="pivot" ' . check_viz_type("pivot") . '/> <b>Top 10 Term Pivot:</b> Show the top 10 most mentioned terms for each media source that occur in stories along with the specified term. (eg: "Show me the terms which occur most frequently in stories about <i>obama</i>.)"<br clear="all">Term: <input name="pivotterm" type="text" size="15" style="font-style:italic" value="' . $_REQUEST[pivotterm] . '" /><br /><br />';
    $viz_form .= '<input name="viz_type" type="radio" value="map" ' . check_viz_type("map") . '/> <b>World Map:</b> Show a world map of each media source, with darker colors indicating more coverage of those countries.<br clear="all"><br />';

    $viz_form .= '</div>';

    $dberror = '';

    $dbconn = connect_to_db(&$dberror);
    if ($dberror != '') { return output_db_error($dberror); }

    $viz_form .= '<script type="text/javascript">var mediaList = [];';

    $result = pg_query('select max(media_id) as max_media_id from media') or $dberror = 'Query failed: ' . pg_last_error();
    if ($dberror != '') { return output_db_error($dberror); }


    $line = pg_fetch_array($result, null, PGSQL_ASSOC);

    $max_media_id = $line[max_media_id];

    // fill mediaList array with blank values otherwise autocompleter crashes
    // when we skip id's
    $viz_form .= "
	for (i=0;i<=$max_media_id;i++) {
    mediaList[i] = '';}";

    $result = pg_query('select * from media where media.media_id not in (select media.media_id from media, tags, media_tags_map where media.media_id=media_tags_map.media_id and tags.tags_id=media_tags_map.tags_id and tags.tag = \'deleteme\') order by name asc') or $dberror .= 'Query failed: ' . pg_last_error();
    if ($dberror != '') { return output_db_error($dberror); }

    $media_list[] = '';

    $i = 0;
    while ($line = pg_fetch_array($result, null, PGSQL_ASSOC)) {
        $i++;
        $theline=$line["name"];
        $theline=preg_replace('/(\n|\r|\)|\(|\|)/', '', $theline);
        $theline = rtrim($theline);
        $theline = ltrim($theline);
        $viz_form .= "mediaList[" . $line[media_id] . "] = '" . addslashes(strip_tags($theline)) . "';\n";
    }
    $viz_form .= '</script>';

    $media_source_request = $_REQUEST[media_source];

    $viz_form .= '<div width="50%" style="float:right; width:50%; padding:10px;">';

    $viz_form .= '<b>Step 2: Choose Up To Three Sources:</b><br /><i>(Just start typing: eg. New York Times)</i><br /><br />';

    for ($i=1;$i<=3;$i++) {
        $viz_form .= '
		<input id="media_source[' . $i . ']" name="media_source[' . $i . ']" autocomplete="off" size="30" type="text" value="' . stripslashes($media_source_request[$i]) . '" onkeyup=\'mc_check_media_name_and_fill_media_id(mediaList,this,"media_id[' . $i . ']");\' onfocus=\'mc_check_media_name_and_fill_media_id(mediaList,this,"media_id[' . $i . ']");\' /><input id="media_id[' . $i . ']" name="media_id[' . $i . ']" size="40" type="hidden" /><br /><br />';
        $viz_form .= '
  	<script type="text/javascript">new Autocompleter.Local(\'media_source[' . $i . ']\', \'media_list\', mediaList, { partialSearch: true, fullSearch: true});</script>';
    }
    $viz_form .= '</div>';

    $viz_form .= "<div style='text-align: center;'><br clear='all'><input type='submit' id='submit' name='submit' /></div></form>";

    $content=str_replace($replace_tag, $viz_form, $content);

    pg_close($dbconn);

    return $content;
}


function insert_mcviz_results($content) {

    $replace_tag = "mcvizresults";
    if (!preg_match("/mcvizresults/", $content)) {
        return $content;
    }


    $viz_link_comment_javascript = '<div style="text-align:center"><input type="submit" value="Insert Visualization Link into Comment Box Below" onclick="document.forms.commentform.comment.value+=\'[REPLACE THIS WITH YOUR COMMENTS ABOUT THE VISUALIZATION]\n<a href=\' + document.location + \'>My Visualization</a>\';" /></div>';



    if ($_REQUEST["viz_type"] == "pivot") {

        if ($_REQUEST["media_id"][1] == "") {
            return output_error("You did not enter a media source to chart.\n");
        }
        if (preg_match("/^\s*$/", $_REQUEST["pivotterm"])) {
            return output_error("You did not enter a term on which to pivot.\n");
        }

        $dbconn = connect_to_db(&$dberror);
        if ($dberror != '') { return output_db_error($dberror); }


        $tagcounts = array();
        $medianum = 0;

        foreach ($_REQUEST["media_id"] as $cur_media_id) {
            if ($cur_media_id == '') { continue; }

            $query = '';
            $result = '';
            $data = '';
            $tags = '';
            $title = '';
            $max_tag_count = '';
            $line = '';

            $pivotterm = strtolower($_REQUEST["pivotterm"]);

            $pivtotterm = preg_replace("/[^a-zA-Z0-9s]/", "", $pivotterm);

            $sub_result = pg_query_params("SELECT * FROM tag_lookup where word = $1 ", array($pivotterm));

            if (pg_num_rows( $sub_result) == 0 ) {
                pg_query_params("insert into tag_lookup(word, tag_sets_id, tags_id) select $1, $2, tags_id from tags where tag_sets_id = $2 and (tag = $1 or split_part(tag, ' ', 1) = $1 or split_part(tag, ' ', 2) = $1 or split_part(tag, ' ', 3) = $1) order by tags_id limit 20;", array($pivotterm,  $_REQUEST["tagset"]));
            }

            // or split_part(t.tag, ' ', 1) = '$pivotterm' or split_part(t.tag, ' ', 2) = '$pivotterm' or split_part(t.tag, ' ', 3) = '$pivotterm'
            $query = "select max(c.tag_count) as max_tag_count, m.name, tt.tag from media_tag_tag_counts c, tag_lookup t, tags tt, media m "
                . "where c.tag_tags_id = tt.tags_id and (t.word = '$pivotterm' ) "
                . "and c.tags_id = t.tags_id and c.media_id = '$cur_media_id' and m.media_id = c.media_id and "
                . "t.tag_sets_id = "
                . $_REQUEST["tagset"] . " and "
                . "tt.tag_sets_id = "
                . $_REQUEST["tagset"]
                . "group by tt.tags_id, m.name, tt.tag order by max_tag_count desc limit 10";

            //$chart .= "$query<br/>";

            $result = pg_query($query) or $dberror .= 'Query failed: ' . pg_last_error();
            if ($dberror != '') { return output_db_error($dberror); }



            while ($line = pg_fetch_array($result, null, PGSQL_ASSOC)) {

                /* foreach ($line as $col_value) {
			$chart .= " | $col_value";
    	}
    		$chart .= "<br/>";*/

                // TODO: Fix this hack, which gives weird results unless max count is first (but in our case should always be true)
                $max_tag_count = max($max_tag_count, $line[max_tag_count]);


                $data .= round($line["max_tag_count"]/$max_tag_count*100) . ",";

                $shorttag = $line["tag"];
                if (strlen($shorttag)>13) {
                    $shorttag = substr($shorttag, 0, 13) . "...";
                }

                $tags = $shorttag . "|" . $tags;

                // TODO: Don't do this on every loop, instead do separate query?
                $title = $line["name"];
                if (strlen($title)>23) {
                    $title = substr($title, 0, 23) . "...";
                }

                $tagcounts[$line["tag"]][$medianum] = $line["max_tag_count"];


            }
            $medianum++;



            //remove trailing comma - I should probably switch it to join() above
            $data = substr($data, 0, -1);

            if ($max_tag_count == '' || $max_tag_count == 0) {
                $chart .= "<br />(<b>No results for source $medianum.</b>  The available terms that you can currently serach for are focused on prominent people, places, and events.  This will broaden considerably in the future.)<br />";
            } else {
                $chart .= "<img src=\"http://chart.apis.google.com/chart?&cht=bhs&chs=200x300&chd=t:$data&chxt=y&chxl=0:|$tags&chtt=$title&chxs=0,,9&chts=000000,11\" />";
            }



            // while ($line = pg_fetch_array($result, null, PGSQL_ASSOC)) {
            //foreach ($line as $col_value) {
            // //$media_name = $
            // $chart .= " | $col_value";
            //}
            // $chart .= "<br/>";
            //}
            //$chart .= "<br/><br/>";



        }

        // sum for each tag, find max
        // print with scaling
        //Print_r ($tagcounts);

    } elseif ($_REQUEST["viz_type"] == "top10") {


        //$chart .= "<br>top10<br>";

        if ($_REQUEST["media_id"][1] == "") {
            return $content;
        }
        foreach ($_REQUEST["media_id"] as $cur_media_id) {


            if ($cur_media_id == '') { continue; }

            $dbconn = connect_to_db(&$dberror);
            if ($dberror != '') { return output_db_error($dberror); }

            $query = '';
            $result = '';
            $data = '';
            $tags = '';
            $title = '';
            $max_tag_count = '';
            $line = '';

            $query = "select m.name, c.* from top_ten_tags_for_media c, media m "
                . "where c.media_id = $cur_media_id and m.media_id = c.media_id and c.tag_sets_id =" .
                $_REQUEST["tagset"] .
                " order by c.media_tag_count desc limit 10";
            //die("$query");

            //$chart .= $query;

            $result = pg_query($query) or $dberror .= 'Query failed: ' . pg_last_error();

            while ($line = pg_fetch_array($result, null, PGSQL_ASSOC)) {

                /* foreach ($line as $col_value) {
			$chart .= " | $col_value";
    	}
    		$chart .= "<br/>";*/

                // TODO: Fix this hack, which gives weird results unless max count is first (but in our case should always be true)
                $max_tag_count = max($max_tag_count, $line[media_tag_count]);


                $data .= round($line["media_tag_count"]/$max_tag_count*100) . ",";

                $shorttag = $line["tag_name"];
                if (strlen($shorttag)>13) {
                    $shorttag = substr($shorttag, 0, 13) . "...";
                }

                $tags = $shorttag . "|" . $tags;

                // TODO: Don't do this on every loop, instead do separate query?
                $title = $line["name"];
                if (strlen($title)>23) {
                    $title = substr($title, 0, 23) . "...";
                }

            }
            //remove trailing comma - I should probably switch it to join() above
            $data = substr($data, 0, -1);

            $chart .= "<img src=\"http://chart.apis.google.com/chart?&cht=bhs&chco=70c44b&chs=200x300&chd=t:$data&chxt=y&chxl=0:|$tags&chtt=$title&chxs=0,,9&chts=000000,11\" />";


            pg_close($dbconn);

        }

    } elseif ($_REQUEST["viz_type"] == "map") {
        if ($_REQUEST["media_id"][1] == "") {
            return output_error("You did not enter a media source to chart.\n");
        }

        $dbconn = connect_to_db(&$dberror);
        if ($dberror != '') { return output_db_error($dberror); }

        //$chart .= "<br>map:<br>";

        $chart .= "<div style='text-align: center;'>";
        foreach ($_REQUEST["media_id"] as $cur_media_id) {
            if ($cur_media_id == '') { continue; }
            $query = "select chart_url, m.name as name from media_google_charts_map_url as u, media as m where u.media_id = m.media_id and u.media_id = $cur_media_id and chart_type_is_log is " . $_REQUEST["chart_is_log"] . " and tag_sets_id='" . $_REQUEST["tagset"] . "'";
            $result = pg_query($query) or $dberror .= 'Query failed: ' . pg_last_error();
            if ($dberror != '') { return output_db_error($dberror); }
            $line = pg_fetch_array($result, null, PGSQL_ASSOC);
            //print_r($line); echo "<br /><br />";
            $chart .= $line[name] . ":<br />";
            $chart .= "<img src=\"$line[chart_url]\"><br clear='all'><br />";
        }
        $chart .= "</div>";

        pg_close($dbconn);

    } else {
        $chart .= "<br/>No visualisation type specified.</br>*" . addslashes($_REQUEST["viz_type"]) . "*";
    }

    $content=str_replace("$replace_tag", $chart, $content);


    return $content;


}


function connect_to_db($thedberror) {

    $dbconn = pg_connect("host=clem dbname=mediacloudwordpresstmp user=mediacloudwordpress password=dkfSDFSD2124sss port=5432") or $thedberror = 'PostgreSQL error: Could not connect: ' . pg_last_error();
    //$dbconn = pg_connect("host=localhost dbname=mediacloud_drl_dev user=mediacloud_drl_dev password=ZeRULVj5nw port=5432") or $thedberror = 'PostgreSQL error: Could not connect: ' . pg_last_error();

    return $dbconn;

}


function output_db_error($dberror) {

    return "<br /><div id='notice' style=\"width:50%; margin:20px; padding:5px\">The Media Cloud database is temporarily offline.  Charts will not work until it returns.  Our apologies.<!-- " . addslashes(strip_tags($dberror)) . " --></div><br clear='all' />" . $content;

}


function output_error($error) {

    return "<br /><div id='notice' style=\"width:50%; margin:20px; padding:5px\">Error: " . addslashes(strip_tags($error)) . "<!-- " . addslashes(strip_tags($error)) . " --></div><br clear='all' />" . $content;

}


?>
