function latest_report_look_up() {

    // TEMPORARY HACK
    //mediacloud.org is password protected so we can't pull from it directly
    // instead we pull from 'https://blogs.law.harvard.edu/mediacloud2/feed/' and dynamically rewrite the URLs to point to mediacloud.org/blog;
    var feed_url = 'https://blogs.law.harvard.edu/mediacloud2/tag/weekly_report/feed/';

    //alert(google_url);
    yql_lookup("select * from rss where url = '" + feed_url + "'", function (response) {

        var results = response.query.results;

	var news_items = $('#weekly_report_link');

        //console.log(results);
        news_items.children().remove();
        news_items.html('');

        $.each($(results.item).first(), function (index, element) {
            var title = element.title;
            var link = element.link;

	    link = link.replace('https://blogs.law.harvard.edu/mediacloud2/', 'http://www.mediacloud.org/blog/');
            news_items.append($('<a/>', {
                'href': link
            }).text(title)).append('<br/>');
        });

    });
}
