function latest_report_look_up() {

    // TEMPORARY HACK
    //mediacloud.org is password protected so we can't pull from it directly
    // instead we pull from 'https://blogs.law.harvard.edu/mediacloud2/feed/' and dynamically rewrite the URLs to point to mediacloud.org/blog;
    var feed_url = 'https://blogs.law.harvard.edu/mediacloud2/tag/weekly_report/feed/';

    //alert(google_url);
    $('#weekly_report_link').html('<p>Loading...</p>');
    yql_lookup("select * from rss where url = '" + feed_url + "'", function (response) {

        var results = response.query.results;

	var news_items = $('#weekly_report_link');

        //console.log(results);
        news_items.children().remove();
        news_items.html('');

        $.each($(results.item).first(), function (index, element) {
            var title = element.title;
            var link = element.link;

	    var description = element.description;

	    var temp = $('<span/>').html(description);

	    var description_text = temp.text();

	    description_text = description_text.replace('Continue reading →', '');

	    

	    link = link.replace('https://blogs.law.harvard.edu/mediacloud2/', 'http://www.mediacloud.org/blog/');
            news_items.append($('<a/>', {
                'href': link
		    }).text(title));

	    news_items.append(':');

            news_items.append('<br/>');
	    news_items.append($(' :<span id="weekly_report_description"/>')
			  .text(description_text).append('<br/>'));
        });

    });
}
