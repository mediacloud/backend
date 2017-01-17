""" Functions for manipulating solr queries """

import io

from tokenize import generate_tokens

from mediawords.util.perl import decode_string_from_bytes_if_needed

# parser object types
TYPE_OPEN   = 'open paren'
TYPE_CLOSE  = 'close paren'
TYPE_PHRASE = 'phrase'
TYPE_AND    = 'and'
TYPE_OR     = 'or'
TYPE_NOT    = 'not'
TYPE_FIELD  = 'field'
TYPE_TERM   = 'term'
TYPE_NOOP   = 'noop'
TYPE_WILD   = 'wildcard'

class ParseNode:
    """ indidividual element of the parse tree """

    def __init__( self, type, value ):
        self.type = type
        self.value = value

class ParseSyntaxError( Exception ):
    """ error class for syntax errors encountered when parsing """
    pass


def _check_type( token, type, want_type ):
    """ throw a ParseSyntaxError if the given type is not in the want_type list """
    if ( not ( type in want_type ) ):
        error = "token '" + token + "' is a token of type " + type + \
            " where one of the following types is expected: " + ', '.join( want_type )
        raise( ParseSyntaxError( error ) )


def _parse_tokens( tokens, want_type = None ):
    """ given a flat list of tokens, generate a boolean logic tree """

    if ( want_type is None ):
        want_type = [ TYPE_OPEN, TYPE_PHRASE, TYPE_NOT, TYPE_FIELD, TYPE_TERM ]

    token = tokens.pop( 0 )

    print( "parse " + token );

    if ( token == '(' ):
        _check_type( token, TYPE_OPEN, want_type )

        clause = None

        while ( len( tokens ) > 0 ):
            want_type = want_type + [ TYPE_CLOSE, TYPE_AND, TYPE_OR, TYPE_WILD ];

            node = _parse_tokens( tokens, want_type )
            if ( node.type == TYPE_CLOSE ):
                break

            elif ( node.type in ( TYPE_AND, TYPE_OR ) ):
                operand_1 = clause
                operand_2 = _parse_tokens( tokens, [ TYPE_OPEN, TYPE_PHRASE, TYPE_NOT, TYPE_FIELD, TYPE_TERM ] );
                node.value = [ operand_1, operand_2 ]
                clause = node

            elif ( node.type == TYPE_FIELD ):
                if ( not ( clause and ( clause.type == TYPE_TERM ) ) ):
                    raise( ParseSyntaxError( 'expect field name before colon' ) )
                field_clause = _parse_tokens( tokens, [ TYPE_OPEN, TYPE_PHRASE, TYPE_TERM ] )
                clause = ParseNode( TYPE_FIELD, [ clause.value, field_clause ] )

            elif ( node.type == TYPE_WILD ):
                if ( not ( clause and ( clause.type == TYPE_TERM ) ) ):
                    raise( ParseSyntaxError( 'expect term before *' ) )
                clause = ParseNode( TYPE_WILD, clause )

            else:
                # if the node is not a boolean operator and there is a previous node in the list, that means we hit
                # two operands in a row with no operator.  in that case, we add an implict 'or' token.
                if ( clause ):
                    clause = ParseNode( TYPE_OR, [ clause, node ] )
                else:
                    clause = node

        return clause

    elif ( token == ')' ):
        _check_type( token, TYPE_CLOSE, want_type )
        return ParseNode( TYPE_CLOSE, None )

    elif ( token[ 0 ] in "'\"" ):
        _check_type( token, TYPE_PHRASE, want_type )
        token = token( 1, -1 )
        terms = map( lambda x: x.lower(), token.split() )
        return ParseNode( 'and', terms )

    elif ( token.lower() == 'and' ):
        _check_type( token, TYPE_AND, want_type )
        return ParseNode( TYPE_AND, None )

    elif ( token.lower() == 'or' ):
        _check_type( token, TYPE_OR, want_type )
        return ParseNode( TYPE_OR, None )

    elif ( token == '*' ):
        _check_type( token, TYPE_WILD, want_type )
        return ParseNode( TYPE_WILD, None )

    elif ( token.lower() in ( 'not', '!' ) ):
        _check_type( token, TYPE_NOT, want_type )
        want_type = [ TYPE_OPEN, TYPE_PHRASE, TYPE_FIELD, TYPE_TERM ]
        return ParseNode( 'not', _parse_tokens( tokens, want_type ) )

    elif ( token == ':' ):
        _check_type( token, TYPE_FIELD, want_type )
        return ParseNode( 'field', None );

    else:
        _check_type( token, TYPE_TERM, want_type )
        return ParseNode( 'term', token )

def _get_plain_query( tree ):
    print( tree.type )
    if ( tree.type == TYPE_OPEN ):
        return '( ' + _get_plain_query( tree.value ) + ' )'
    elif( tree.type == TYPE_TERM ):
        return str( tree.value )
    elif( tree.type == TYPE_NOT ):
        return 'not ' + _get_plain_query( tree.value )
    elif( tree.type == TYPE_WILD ):
        return _get_plain_query( tree.value ) + '*'
    elif( tree.type == TYPE_AND ):
        return '( ' + _get_plain_query( tree.value[ 0 ] ) + ' and ' + _get_plain_query( tree.value[ 1 ] ) + ' )'
    elif( tree.type == TYPE_OR ):
        return '( ' + _get_plain_query( tree.value[ 0 ] ) + ' or ' + _get_plain_query( tree.value[ 1 ] ) + ' )'
    elif( tree.type == TYPE_FIELD ):
        return tree.value[ 0 ] + ":" + _get_plain_query( tree.value[ 1 ] )
    else:
        return '[ INVALID NODE TYPE ' + tree.type + ' ]'


def convert_to_tsquery ( solr_query ):
    """ convert a solr query to an equivalent tsquery for use in postgres """

    solr_query = decode_string_from_bytes_if_needed( solr_query )\

    solr_query = "( " + solr_query + " )"

    full_tokens = generate_tokens(io.StringIO( solr_query ).readline )

    tokens = []
    for token in full_tokens:
        tokens.append( token[1] )

    print( tokens )

    tree = _parse_tokens( tokens )

    query = _get_plain_query( tree )

    print( query )

    return query
