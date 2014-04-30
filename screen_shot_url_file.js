
var fs = require('fs');
var page = require('webpage').create();

function capture_func( q0, q1 )
{
    console.log('capturing');

    console.log(q0);

    //q0 = 94946;

    url = 'http://www.mediacloud.org/dashboard/view/1?q1=' + q0;
    console.log( url );

    url = 'http://www.mediacloud.org/dashboard/view/1?q1=94946';

    var page = require('webpage').create();

    page.open(url, function() {
	    console.log('rendering');
	page.render('mc_' + q0 + '.png');
	page.render('mc_' + q0 + '.pdf');
	page.render('mc_' + q0 + '.jpg');
	console.log('captured');
	//phantom.exit();
    });
}

var stream = fs.open('/tmp/CSV_FILE.csv', 'r');

var header_line = stream.readLine();

header_arr = header_line.split( "\t" );

//console.log( header_arr );
//console.assert(header_arr.1 == 'queries_id_0');
//console.assert( header_arr.2 == 'queries_id_1');

//phantom.exit();

while(!stream.atEnd()) {
    var line = stream.readLine();
    //console.log(line);
    fields = line.split( "\t" );
    console.log(fields);
    //console.log(fields.length() + '');
    var q0 = fields[1];
    var q1 = fields[2];

    console.log( q0 );
    console.log( 'q0=' + q0 );
    //q0 = 94946;
    capture_func( q0, q1 );
}

stream.close();
//phantom.exit();

