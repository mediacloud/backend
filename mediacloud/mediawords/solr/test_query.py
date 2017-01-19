from nose.tools import assert_raises
from nose.tools import assert_equals

from mediawords.solr.query import *

def test_query():

    assert_raises( ParseSyntaxError, parse, "and" )

    assert_raises( ParseSyntaxError, parse, "and" )

    assert_raises( ParseSyntaxError, lambda x: parse( x ).tsquery(), "media_id:1" )

    assert_raises( ParseSyntaxError, parse, '"foo bar"~3' )

    assert_raises( ParseSyntaxError, parse, '"foo bar"~3' )

    assert_raises( ParseSyntaxError, parse, '( foo bar )*' )

    assert_equals( parse( 'foo and bar' ).tsquery(), '( foo & bar )' )

    assert_equals( parse( '( foo )' ).tsquery(), 'foo' )

    assert_equals( parse( '( foo and bar )' ).tsquery(), '( foo & bar )' )

    assert_equals( parse( 'foo' ).tsquery(), 'foo' )

    assert_equals( parse( 'foo bar' ).tsquery(), '( foo | bar )' )

    assert_equals( parse( 'foo and ( bar baz )' ).tsquery(), '( foo & ( bar | baz ) )' )

    assert_equals( parse( '( foo or bat ) and ( bar baz )' ).tsquery(), '( ( foo | bat ) & ( bar | baz ) )' )

    assert_equals( parse( 'foo and bar and baz and bat' ).tsquery(), '( foo & bar & baz & bat )' )

    assert_equals( parse( 'foo and bar and baz and bat and ( 1 2 3 )' ).tsquery(), '( foo & bar & baz & bat & ( 1 | 2 | 3 ) )' )

    assert_equals( parse( 'not ( foo bar )' ).tsquery(), '!( foo | bar )' )

    assert_equals( parse( '"foo bar-baz"' ).tsquery(), "( foo & bar & baz )" )

    assert_equals( parse( '( 1 or 2 or 3 or 4 )' ).tsquery(), '( 1 | 2 | 3 | 4 )' )

    assert_equals( parse( '1 or 2 or "foo bar-baz"' ).tsquery(), "( 1 | 2 | ( foo & bar & baz ) )" )

    assert_equals( parse( '( 1 or 2 or 3 ) and "foz fot"' ).tsquery(), "( ( 1 | 2 | 3 ) & foz & fot )" )

    assert_equals( parse( '( 1 or 2 or "foo bar-baz" ) and "foz fot"' ).tsquery(), "( ( 1 | 2 | ( foo & bar & baz ) ) & foz & fot )" )

    assert_equals( parse( 'media_id:1 and foo' ).tsquery(), "( foo )" )

    assert_equals( parse( 'foo +bar baz' ).tsquery(), "( ( foo & bar ) | baz )" )

    assert_equals( parse( 'foo or +bar baz' ).tsquery(), "( foo | bar | baz )" )

    assert_equals( parse( '+bar baz' ).tsquery(), "( bar | baz )" )

    assert_equals( parse( 'foo*' ).tsquery(), "foo:*" )

    assert_equals( parse( '( foo* bar ) and baz*' ).tsquery(), "( ( foo:* | bar ) & baz:* )" )

    assert_equals( parse( '( foo and -bar )' ).tsquery(), '( foo & !bar )' )

    assert_equals( parse( '( foo and not( bar bat ) )' ).tsquery(), '( foo & !( bar | bat ) )' )

    assert_equals( parse( '( foo !"bar bat" )' ).tsquery(), '( foo & !( bar & bat ) )' )


    candidate_query = """
+( fiorina ( scott and walker ) ( ben and carson ) trump ( cruz and -victor ) kasich rubio (jeb and bush) clinton sanders )
AND (+publish_date:[2016-09-30T00:00:00Z TO 2016-11-08T23:59:59Z]) AND ((tags_id_media:9139487 OR
 tags_id_media:9139458 OR tags_id_media:2453107 OR tags_id_stories:9139487 OR tags_id_stories:9139458 OR tags_id_stories:2453107))
"""
    candidate_tsquery = "( ( fiorina | ( scott & walker ) | ( ben & carson ) | trump | ( cruz & !victor ) | kasich | rubio | ( jeb & bush ) | clinton | sanders ) )"

    assert_equals( parse( candidate_query ).tsquery(), candidate_tsquery )
