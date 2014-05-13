
var fs = require('fs');
//var page = require('webpage').create();

function capture_and_render( url, base_name )
{
    var page = require('webpage').create();

    var output_dir = 'screen_shots';

    console.log( 'capture_and_render: ' + url );

    page.open(url, function() {
	console.log('rendering' + url);
	console.log('base_name:' + base_name );

	page.render(output_dir + '/' + base_name + '.png');
	page.render(output_dir + '/' + base_name + '.pdf');
	console.log('captured');
	phantom.exit();
    });

}

function capture_func( q0, q1, wc_only )
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

    if ( ! wc_only ) 
    {
	capture_and_render( 'http://www.mediacloud.org/dashboard/view/1?q1=' + q0 + '&q2=' + q1, 'mc_' + q0 + '_' + q1 );
    }
    else
    {

//    var url_2 = url + '&wconly=1';

	capture_and_render( 'http://www.mediacloud.org/dashboard/view/1?q1=' + q0 + '&q2=' + q1 + '&wconly=1', 'mc_wconly_' + q0 + '_' + q1 );
    }
}


system = require('system'),

q0 = system.args[1]
q1 = system.args[2]

var wc_only = false;

if ( system.args.length > 2 && system.args[3] == '--wc_only' )
{
    wc_only = true;
}
capture_func( q0, q1, wc_only );
