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

def get_solr_query( tree ):
    """ convert the parse tree back into a solr query """
    if( tree.type == TYPE_TERM ):
        return str( tree.value )
    elif( tree.type == TYPE_NOT ):
        return 'not ' + get_solr_query( tree.value )
    elif( tree.type == TYPE_WILD ):
        return get_solr_query( tree.value ) + '*'
    elif( tree.type == TYPE_AND ):
        return '( ' + get_solr_query( tree.value[ 0 ] ) + ' and ' + get_solr_query( tree.value[ 1 ] ) + ' )'
    elif( tree.type == TYPE_OR ):
        return '( ' + get_solr_query( tree.value[ 0 ] ) + ' or ' + get_solr_query( tree.value[ 1 ] ) + ' )'
    elif( tree.type == TYPE_FIELD ):
        return tree.value[ 0 ] + ":" + get_solr_query( tree.value[ 1 ] )
    else:
        return '[ INVALID NODE TYPE ' + tree.type + ' ]'

def _get_filtered_tsquery( tree ):
    """ convert the tree into the equivalent postgres tsquery, assuming that any field nodes have been filtered out. """
    if( tree.type == TYPE_TERM ):
        return str( tree.value )
    elif( tree.type == TYPE_NOT ):
        return '!' + _get_filtered_tsquery( tree.value )
    elif( tree.type == TYPE_WILD ):
        return _get_filtered_tsquery( tree.value ) + ':*'
    elif( tree.type == TYPE_AND ):
        return '( ' + ' & '.join( map( lambda x: _get_filtered_tsquery( x ), tree.value ) ) + ' )'
    elif( tree.type == TYPE_OR ):
        return '( ' + ' | '.join( map( lambda x: _get_filtered_tsquery( x ), tree.value ) ) + ' )'
    elif( tree.type == TYPE_FIELD ):
        raise( ParseSyntaxError( "non-default field attributes not allowed" ) )
    else:
        raise( ParseSyntaxError( 'invalid tree type '+ tree.type )

def _filter_fields_from_tree( tree, default_field ):
    """ filter all field clauses from the parse tree other than those for the default_field.  convert searches for the
    default field into a direct search (so 'sentence:( bar and bat )' becomes '( bar and bat )'.
    """

    if ( tree.type == TYPE_FIELD ):
        if ( tree.value[ 0 ] == default_field ):
            return tree.value[ 1 ]
        else:
            return None

    elif( tree.type in ( TYPE_TERM, TYPE_WILD ) ):
        return ParseNode( tree.type, tree.value )

    elif( tree.type in ( TYPE_AND, TYPE_OR ) ):
        filtered_operands = []
        for operand in tree.value:
            filtered_operand = _filter_fields_from_tree( operand, default_field )
            if ( filtered_operand ):
                filtered_operands.append( filtered_operand )

        return ParseNode( tree.type, filtered_operands ) if ( len( filtered_operands ) > 0 ) else None

    elif( tree.type == TYPE_NOT ):
        filtered_operand = _filter_fields_from_Tree( tree.value, default_field )
        return ParseNode( TYPE_NOT, tree.value ) if ( filtered_operand ) else None

]

def get_tsquery( tree ):
    """ convert the tree into mostly equivalent posptgres tsquery

    we can't make an exact equivalent because we can only search text, not other fields, so this function will simply
    remove clauses for any fields other than the default or 'sentence'.  So 'title:foo and bar and sentence:bat' will return
    'bar & bat'.
    """
    tree = _filter_fields_from_tree( tree, 'sentence' )

    return _get_filtered_tsquery( tree )


def parse_solr_query( solr_query ):
    """ Parse a solr query and return a ParseNode object that encapsulates the query in structured form.

    ParseNode has a 'type' and a 'value' attribute.  The type is one of the following: TYPE_TERM, TYPE_NOT, TYPE_AND,
    TYPE_OR, TYPE_WILD, TYPE_FIELD.  The value is the value for the given type, for instance the term for a TYPE_TERM
    node.
    """

    solr_query = decode_string_from_bytes_if_needed( solr_query )\

    solr_query = "( " + solr_query + " )"

    full_tokens = generate_tokens(io.StringIO( solr_query ).readline )

    tokens = []
    for token in full_tokens:
        tokens.append( token[ 1 ] )

    return _parse_tokens( tokens )


def convert_to_tsquery ( solr_query ):
    """ parse a solr query to an equivalent tsquery for use in postgres """

    tree = parse_solr_query( solr_query )

    query = _get_tsquery( tree )

    return query
