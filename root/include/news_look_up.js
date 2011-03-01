
function yql_lookup(query, cb_function) {
    var url = 'http://query.yahooapis.com/v1/public/yql?q=' + encodeURIComponent(query) + '&format=json&diagnostics=true';

    //alert(url);

    $.getJSON(url, cb_function);
}

function look_up_news() {

    var feed_url = 'http://www.mediacloud.org/feed/';

    //alert(google_url);
    yql_lookup("select * from rss where url = '" + feed_url + "'", function (response) {

        var results = response.query.results;

	var news_items = $('#news_items');

        //console.log(results);
        news_items.children().remove();
        news_items.html('');

        $.each(results.item, function (index, element) {
            var title = element.title;
            var link = element.link;

            news_items.append($('<a/>', {
                'href': link
            }).text(title)).append('<br/>');
        });

    });
}
