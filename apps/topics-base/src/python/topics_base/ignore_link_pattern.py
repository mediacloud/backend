# ignore any list that match the below patterns.  the sites below are most social sharing button links of
# various kinds, along with some content spam sites and a couple of sites that confuse the spider with too
# many domain alternatives.
IGNORE_LINK_PATTERN = (
    r'(?:www.addtoany.com)|(?:novostimira.com)|(?:ads\.pheedo)|(?:www.dailykos.com\/user)|'
    r'(?:livejournal.com\/(?:tag|profile))|(?:sfbayview.com\/tag)|(?:absoluteastronomy.com)|'
    r'(?:\/share.*http)|(?:digg.com\/submit)|(?:facebook.com.*mediacontentsharebutton)|'
    r'(?:feeds.wordpress.com\/.*\/go)|(?:sharetodiaspora.github.io\/)|(?:iconosquare.com)|'
    r'(?:unz.com)|(?:answers.com)|(?:downwithtyranny.com\/search)|(?:scoop\.?it)|(?:sco\.lt)|'
    r'(?:pronk.*\.wordpress\.com\/(?:tag|category))|(?:wn\.com)|(?:pinterest\.com\/pin\/create)|(?:feedblitz\.com)|'
    r'(?:atomz.com)|(?:unionpedia.org)|(?:http://politicalgraveyard.com)|(?:https?://api\.[^\/]+)|'
    r'(?:www.rumormillnews.com)|(?:tvtropes.org/pmwiki)|(?:twitter.com/account/suspended)|'
    r'(?:feedsportal.com)')
