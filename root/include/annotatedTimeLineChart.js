
function annotatedTimeLineChart(chart_element, url, dataString) {
    var chart_element = $('#line_chart');

    chart_element.text('Loading...');

    $.ajax({
	    url: url,
        //dataType: 'json',
        //timeout: 30000,
        data: dataString,
        success: function (data_perl) {


            //var data_json = eval (data_perl);
            var data = new google.visualization.DataTable(data_perl, 0.6);

            //var chart_placement =  document.getElementById('line_chart');
            var chart = new google.visualization.AnnotatedTimeLine(chart_element.get(0));

            var json = data.toJSON();

            //alert(json);
            chart.draw(data, {
                displayAnnotations: true
            });

            //alert(data.toJSON() );

        },
        error: function (jqXHR, textStatus, errorThrownsuccess) {
            alert(textStatus);
        }
    });

}