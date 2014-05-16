var fs = require('fs');
var page = require('webpage').create();

var stream =  fs.open('/tmp/json2', 'r');
var json_str = stream.readLine();

var data = JSON.parse(json_str);

function capture_and_render( url, base_name )
{
    //var page = require('webpage').create();


    var output_dir = 'screen_shots';


    console.log( 'capture_and_render: ' + url );


    return page.open(url, function() {
      console.log('rendering' + url);
      console.log('base_name:' + base_name );


      page.render(output_dir + '/' + base_name + '.png');
      //page.render(output_dir + '/' + base_name + '.pdf');
      console.log('captured');

      setTimeout( next, 33 );
    });
}


function capture_func( q0, q1 )
{
    console.log('capturing');
    console.log(q0);


    //q0 = 94946;




    if ( ! q1 )
    {
	q1 = '';
    }


    var url = 'http://www.mediacloud.org/dashboard/view/1?q1=' + q0;
    console.log( url );


    return capture_and_render( 'http://www.mediacloud.org/dashboard/view/1?q1=' + q0 + '&q2=' + q1, 'mc_' + q0 + '_' + q1 );


//    var url_2 = url + '&wconly=1';


    //capture_and_render( 'http://www.mediacloud.org/dashboard/view/1?q1=' + q0 + '&q2=' + q1 + '&wconly=1', 'mc_wconly_' + q0 + '_' + q1 );
    
    /*
    var page_2 =  require('webpage').create();


    var output_dir = 'screen_shots';


    page_2.open(url_2, function(status) {
	console.log('rendering' + url_2);
	console.log( status );
	page_2.render(output_dir + '/mc_' + q0 + '_wc_only' + '.png');
	page_2.render(output_dir + '/mc_' + q0 + '_wc_only' + '.pdf');
	console.log('captured');
	//phantom.exit();
    });
*/
}



//stream.close();

function next() {
  if ( data.length > 0 ) {
    item = data.pop();

    var q0 = item[  "queries_id_0" ];
    var q1 = item[  "queries_id_1" ];
    capture_func( q0, q1 );
  } else {
    phantom.exit();
  }
}

next();

/*
data.forEach( function( pop_query ) {
    var q0 = pop_query[  "queries_id_0" ];
    var q1 = pop_query[  "queries_id_1" ];
    console.log( 'q0: ' + q0 + ', q1: ' + q1 );
    pages_to_render.push( capture_func( q0, q1 ) );
});
*/


