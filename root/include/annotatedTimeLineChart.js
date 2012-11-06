
 google.load('visualization', '1', {'packages':['annotatedtimeline']});




function annotatedTimeLineChart(chart_element, url, dataString) {

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
                displayAnnotations: true,
		        legendPosition: 'newRow'
		        colors: [ '#2ca02c', '#1f77b4', '#aec7e8', '#ff7f0e', '#ffbb78', '#98df8a', '#d62728', '#ff9896', '#9467bd', '#c5b0d5', '#8c564b', '#c49c94', '#e377c2', '#f7b6d2', '#7f7f7f', '#c7c7c7', '#bcbd22', '#dbdb8d', '#17becf', '#9edae5', '#84c4ce', '#ffa779', '#cc5ace', '#6f11c9', '#6f3e5d' ] } );

            //alert(data.toJSON() );

        },
        error: function (jqXHR, textStatus, errorThrownsuccess) {
            alert(textStatus);
        }
    });

}