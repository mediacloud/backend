# ignore any list that match the below patterns\.  the sites below are most social sharing button links of
# various kinds, along with some content spam sites and a couple of sites that confuse the spider with too
# many domain alternatives\.
__ignore_link_patterns = [
    r'www\.addtoany\.com',
    r'novostimira\.com',
    r'ads\.pheedo',
    r'www\.dailykos\.com/user',
    r'livejournal\.com/(?:tag|profile)',
    r'sfbayview\.com/tag',
    r'absoluteastronomy\.com',
    r'/share\.*http',
    r'digg\.com/submit',
    r'facebook\.com\.*mediacontentsharebutton',
    r'feeds\.wordpress\.com/.*\/go',
    r'sharetodiaspora\.github\.io\/',
    r'iconosquare\.com'
    r'unz\.com',
    r'answers\.com',
    r'downwithtyranny\.com\/search',
    r'scoop\.?it',
    r'sco\.lt',
    r'pronk\.*\.wordpress\.com\/(?:tag|category)',
    r'[\./]wn\.com',
    r'pinterest\.com/pin/create',
    r'feedblitz\\.com',
    r'atomz\.com',
    r'unionpedia\.org',
    r'https?://politicalgraveyard\.com',
    r'https?://api\.[^\/]+',
    r'www\.rumormillnews\.com',
    r'tvtropes\.org/pmwiki',
    r'twitter\.com/account/suspended',
    r'feedsportal\.com',
    r'misuse\.ncbi\.nlm\.nih\.gov/error/abuse\.shtml', # we get blocked by nih, and everything ends up here
    r'assets\.feedblitzstatic\.com/images/blank\.gif',
    r'accounts\.google\.com/ServiceLogin',
    r'network\.wwe\.com/video', # wwe videos just redirect to front page
    r'goldfish\.me/',
    r'uscode\.house\.gov/quicksearch', # political topics try to download entire database
]

IGNORE_LINK_PATTERN = '|'.join(["(?:%s)" % p for p in __ignore_link_patterns])
