
function yql_lookup(query, cb_function) {
    var url = 'http://query.yahooapis.com/v1/public/yql?q=' + encodeURIComponent(query) + '&format=json&diagnostics=true';

    //alert(url);

    $.ajax({
  url: url,
  dataType: 'json',
 success: cb_function,
 error: function(jqXHR, textStatus, errorThrown)
 {
    alert('Error: ' + textStatus);
}
});
    // $.getJSON(url, cb_function);
}

function look_up_news() {

    // TEMPORARY HACK
    //mediacloud.org is password protected so we can't pull from it directly
    // instead we pull from 'https://blogs.law.harvard.edu/mediacloud2/feed/' and dynamically rewrite the URLs to point to mediacloud.org/blog;
    var feed_url = 'https://blogs.law.harvard.edu/mediacloud2/feed/';

    //alert(google_url);
    $('#news_items').html('<p>Loading...</p>');
    yql_lookup("select * from rss where url = '" + feed_url + "'", function (response) {

        var results = response.query.results;

	var news_items = $('#news_items');

        //console.log(results);
        news_items.children().remove();
        news_items.html('');

        $.each(results.item, function (index, element) {
            var title = element.title;
            var link = element.link;

	    link = link.replace('https://blogs.law.harvard.edu/mediacloud2/', 'http://www.mediacloud.org/blog/');
            news_items.append($('<a/>', {
                'href': link
            }).text(title)).append('<br/>');
        });

    });
}
