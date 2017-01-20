""" Functions for manipulating solr queries """

import inspect
import io
import shlex
import re

from tokenize import generate_tokens

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_string_from_bytes_if_needed

l = create_logger(__name__)

# token types
T_OPEN   = 'open paren'
T_CLOSE  = 'close paren'
T_PHRASE = 'phrase'
T_AND    = 'and'
T_OR     = 'or'
T_NOT    = 'not'
T_FIELD  = 'field'
T_TERM   = 'term'
T_PLUS   = 'plus'
T_MINUS  = 'minus'
T_NOOP   = 'noop'

# this text will be considered a noop token
NOOP_PLACEHOLDER = '__NOOP__'

# replace ':' with this before tokenization so that it gets included with the field name
FIELD_PLACEHOLDER = '__FIELD__'

# replace '*' with this before tokenization so that it gets included with the term
WILD_PLACEHOLDER = '__WILD__'

class Token:
    """ object that holds the token value and type.  type should one of T_* above """
    def __init__( self, value, type ):
        self.value = value
        self.type = type

    def __repr__( self ):
        return( "[ %s: %s ]" % ( self.type, self.value ) )

    def __str__( self ):
        return self.__repr__()

def _node_is_field_or_noop( node ):
    """ return true if the field is a non-sentence field or is a noop """

    if ( ( type( node ) is FieldNode ) and ( node.field != 'sentence' ) ):
        return True;
    elif ( type( node ) is NoopNode ):
        return True;

    return False;

def _node_is_field_or_noop_or_not( node ):
    """ return true if the field is a non-sentence field or is a noop """

    if ( ( type( node ) is FieldNode ) and ( node.field != 'sentence' ) ):
        return True;
    elif ( type( node ) in ( NoopNode, NotNode ) ):
        return True;

    return False;


class ParseNode:
    """ parent class for universal methods for *Node classes """

    def __str__( self ):
        return self.__repr__()

    def _filter_boolean_node_children( self, filter_function ):
        boolean_type = type( self )
        filtered_operands = []
        for operand in self.operands:
            filtered_operand = operand.filter_tree( filter_function )
            if ( filtered_operand ):
                filtered_operands.append( filtered_operand )

        return boolean_type( filtered_operands ) if ( len( filtered_operands ) > 0 ) else None


    def filter_tree( self, filter_function ):
        """ filter all nodes from the tree for which filter_function returns tree.
        so if the filter is lamda x: type( x ) is NotNode then '( foo and !bar ) or baz' will be filtered to
        '( foo ) or baz'
        """

        try:
            if ( self.filtered_by_function == filter_function ):
                return self;
        except ( AttributeError ):
            pass

        if ( filter_function( self ) ):
            return None;
        else:
            filtered_tree = self._filter_node_children( filter_function )
            if ( filtered_tree ):
                filtered_tree.filtered_by_function = filter_function
            return filtered_tree

    def tsquery( self ):
        """ return a postgres tsquery that represents the parse tree """

        filtered_tree = self.filter_tree( _node_is_field_or_noop )

        if ( filtered_tree is None ):
            raise( ParseSyntaxError( "query is empty without fields or ranges" ) )

        return filtered_tree._get_tsquery()

    def re( self ):
        """ return a posix regex that represents the parse tree """

        filtered_tree = self.filter_tree( _node_is_field_or_noop_or_not )

        if ( filtered_tree is None ):
            raise( ParseSyntaxError( "query is empty without fields or ranges" ) )

        return filtered_tree._get_re();

class TermNode( ParseNode ):
    """ parse node type for a simple keyword """
    def __init__( self, term, wildcard = False, phrase = False ):
        self.term = term
        self.wildcard = wildcard
        self.phrase = phrase

    def __repr__( self ):
        return self.term if ( not self.wildcard ) else self.term + "*"

    def _get_tsquery( self ):
        if ( self.phrase ):
            dequoted_phrase = shlex.split( self.term )[ 0 ]
            operands = []
            for term in re.split( '\W+', dequoted_phrase ):
                if ( term ):
                    operands.append( TermNode( term ) )

            if ( len( operands ) == 0 ):
                raise( ParseSyntaxError( "empty phrase not allowed" ) )

            return AndNode( operands )._get_tsquery()
        else:
            return self.term if ( not self.wildcard ) else self.term + ":*"

    def _get_re( self ):
        term = self.term
        if ( self.phrase ):
            term = shlex.split( term )[ 0 ]

            # should already be lower case, but make sure
            term = term.lower()

            # replace spaces with placeholder text so that we can replace it with [[:space:]] after re.escape
            term = re.sub( r'\s+', 'SPACE', term )

            term = re.escape( term )
            term = re.sub( 'SPACE', '[[:space:]]+', term )

            return '[[:<:]]' + term
        else:
            return '[[:<:]]' + re.escape( term )

    def _filter_node_children( self, filter_function ):
        return TermNode( self.term, wildcard = self.wildcard, phrase = self.phrase )

class BooleanNode( ParseNode ):
    """ supr class for ands and ors """
    def __init__( self, operands ):
        self.operands = operands
        for operand in operands:
            operand.parent = self

    def _plain_connector( self ):
        raise( AssertionError( "sub class must define _plain_connector" ) )

    def _tsquery_connector( self ):
        raise( AssertionError( "sub class must define _tsquery_connector" ) )

    def __repr__( self ):
        connector = ' ' + self._plain_connector() + ' ';
        return '( ' + connector.join( map ( lambda x:  str( x ), self.operands  ) ) + ' )'

    def _get_tsquery( self ):
        connector = ' ' + self._tsquery_connector() + ' ';
        return '( ' + connector.join( map( lambda x: x._get_tsquery(), self.operands ) ) + ' )'

    def _filter_node_children( self, filter_function ):
        return self._filter_boolean_node_children( filter_function )


class AndNode( BooleanNode ):
    """ parse node for an and clause """
    def _plain_connector( self ):
        return 'and'

    def _tsquery_connector( self ):
        return '&'

    def _get_re( self, operands = None ):
        if ( operands is None ):
            operands = self.operands

        if ( len( operands ) == 1 ):
            return operands[ 0 ]._get_re()
        else:
            a = operands[ 0 ]._get_re()
            b = self._get_re( operands[ 1: ] )
            return '(?: (?: %s .* %s ) | (?: %s .* %s ) )' % ( a, b, b, a );

class OrNode( BooleanNode ):
    """ parse node for an or clause """
    def _plain_connector( self ):
        return 'or'

    def _tsquery_connector( self ):
        return '|'

    def _get_re( self ):
        return '(?: ' + ' | '.join( map( lambda x: x._get_re(), self.operands ) ) + ' )'


class NotNode( ParseNode ):
    """ parse node for a not clause """
    def __init__( self, operand ):
        self.operand = operand
        operand.parent = self

    def __repr__( self ):
        return '!' + str( self.operand )

    def _get_tsquery( self ):
        return '!' + self.operand._get_tsquery()

    def _get_re( self ):
        raise( ParseSyntaxError( "not operations not supported for re()" ) )

    def _filter_node_children( self, filter_function ):
        filtered_operand = self.operand.filter_tree( filter_function )
        return NotNode( filtered_operand ) if ( filtered_operand ) else None


class FieldNode( ParseNode ):
    """ parse node for a field clause """
    def __init__( self, field, operand ):
        self.field = field
        self.operand = operand
        operand.parent = self

    def __repr__( self ):
        return self.field + ':' + str( self.operand )

    def _get_tsquery( self ):
        if ( self.field == 'sentence' ):
            return self.operand._get_tsquery()
        else:
            raise( ValueError( "non-sentence field nodes should have been filtered" ) )

    def _get_re( self ):
        if ( self.field == 'sentence' ):
            return self.operand._get_re()
        else:
            raise( ValueError( "non-sentence field nodes should have been filtered" ) )


    def _filter_node_children( self, filter_function ):
        filtered_operand = self.operand.filter_tree( filter_function )
        return FieldNode( self.field, filtered_operand ) if ( filtered_operand ) else None

class NoopNode( ParseNode ):
    """ parse node for a node that should have no impact on the result of the query """
    def __init__( self ):
        pass

    def __repr__( self ):
        return NOOP_PLACEHOLDER

    def _get_tsquery( self ):
        raise( ValueError( "noop nodes should have been filtered" ) )

    def _get_re( self ):
        raise( ValueError( "noop nodes should have been filtered" ) )

    def _filter_node_children( self, filter_function ):
        return NoopNode()

class ParseSyntaxError( Exception ):
    """ error class for syntax errors encountered when parsing """
    pass


def _check_type( token, want_type ):
    """ throw a ParseSyntaxError if the given type is not in the want_type list """
    if ( not ( token.type in want_type ) ):
        error = "token '" + str( token ) + "' is not one of the following expected types: " + ', '.join( want_type )
        raise( ParseSyntaxError( error ) )


def _parse_tokens( tokens, want_type = None ):
    """ given a flat list of tokens, generate a boolean logic tree """

    l.debug( "parse tree: " + str( tokens ) )

    if ( want_type is None ):
        want_type = [ T_OPEN, T_PHRASE, T_NOT, T_TERM ]

    clause = None
    boolean_clause = None
    hanging_boolean = False

    while ( len( tokens ) > 0 ):

        framedepth = len( inspect.getouterframes( inspect.currentframe() ) )
        l.debug( "clause: %s [%s] [framedepth: %s]" % ( clause, type( clause ), framedepth ) )

        token = tokens.pop( 0 )
        l.debug( "parse token: " + str( token ) )

        if ( ( token.type == T_PLUS ) and ( not clause or ( type( clause ) in ( AndNode, OrNode ) ) ) ):
            continue

        if ( hanging_boolean ):
            boolean_clause = clause
            hanging_boolean = False
        elif ( clause and ( token.type in [ T_OPEN, T_PHRASE, T_TERM, T_NOOP, T_FIELD ] ) ):
            l.debug( "INSERT OR" )
            tokens.insert( 0, token )
            token = Token( T_OR, 'or' );
        elif ( clause and ( token.type in [ T_NOT ] ) ):
            l.debug( "INSERT AND" )
            tokens.insert( 0, token )
            token = Token( T_AND, 'and' );

        _check_type( token, want_type )

        if( token.type == T_OPEN ):
            clause = _parse_tokens( tokens, [ T_OPEN, T_PHRASE, T_NOT, T_FIELD, T_TERM, T_NOOP, T_CLOSE ] )
            want_type = [ T_OPEN, T_PHRASE, T_NOT, T_FIELD, T_TERM, T_NOOP, T_CLOSE, T_AND, T_OR, T_PLUS ]

        elif ( token.type == T_CLOSE ):
            break

        elif ( token.type == T_NOOP ):
            want_type = [ T_CLOSE, T_AND, T_OR, T_PLUS ]
            clause = NoopNode()

        elif ( token.type == T_TERM):
            want_type = [ T_CLOSE, T_AND, T_OR, T_PLUS ]
            wildcard = False
            if ( token.value.endswith( WILD_PLACEHOLDER ) ):
                token.value = token.value.replace( WILD_PLACEHOLDER, '' )
                wildcard = True

            clause = TermNode( token.value, wildcard = wildcard )

        elif( token.type == T_PHRASE ):
            want_type = [ T_CLOSE, T_AND, T_OR, T_PLUS ]
            clause = TermNode( token.value, phrase = True )
            operands = []

        elif ( token.type in ( T_AND, T_PLUS, T_OR ) ):
            want_type = [ T_OPEN, T_PHRASE, T_NOT, T_FIELD, T_TERM, T_NOOP, T_CLOSE, T_PLUS ];

            node_type = OrNode if ( token.type == T_OR ) else AndNode

            if ( type( clause ) is node_type ):
                clause = node_type( clause.operands )
            else:
                clause = node_type( [ clause ] )

            hanging_boolean = True

        elif ( token.type == T_FIELD ):
            want_type = [ T_CLOSE, T_AND, T_OR, T_PLUS ]
            field_name = re.sub( FIELD_PLACEHOLDER, '', token.value )
            next_token = tokens.pop( 0 );
            if ( next_token.type == T_OPEN ):
                field_clause = _parse_tokens( tokens, [ T_PHRASE, T_NOT, T_TERM, T_NOOP, T_CLOSE, T_PLUS ] )
            else:
                field_clause = _parse_tokens( [ next_token ], [ T_PHRASE, T_TERM, T_NOOP ] )

            l.debug( "field operand for %s: %s" % ( field_name, field_clause ) )

            clause = FieldNode( field_name, field_clause )

        elif ( token.type == T_NOT ):
            want_type = [ T_CLOSE, T_AND, T_OR, T_PLUS ]
            operand = None
            next_token = tokens.pop( 0 );
            if ( next_token.type == T_OPEN ):
                operand = _parse_tokens( tokens, [ T_FIELD, T_PHRASE, T_NOT, T_TERM, T_NOOP, T_CLOSE, T_PLUS ] )
            elif ( next_token.type == T_FIELD ):
                tokens.insert( 0, next_token )
                operand = _parse_tokens( tokens, [ T_FIELD ] )
            else:
                operand = _parse_tokens( [ next_token ], [ T_PHRASE, T_TERM, T_NOOP, T_FIELD ] )
            clause = NotNode( operand )

        else:
            raise( ParseSyntaxError( "unknown type for token '%s'" % token ) )

        want_type = want_type + [ T_CLOSE ]

        if ( boolean_clause ):
            l.debug( "boolean append: %s <- %s" % ( boolean_clause, clause ) )
            if ( ( type( boolean_clause ) is type( clause ) ) ):
                boolean_clause.operands += clause.operands
            else:
                boolean_clause.operands.append( clause )
            clause = boolean_clause
            boolean_clause = None


    try:
        l.debug( "parse result: " + str( clause ) )
    except:
        l.debug( "parse_result: [" + str( type( clause ) ) + "]" );

    return clause

def _get_token_type( token ):
    """ given some token text, return one of T_* as the type for that token """

    if ( token == '(' ):
        return T_OPEN
    elif ( token == ')' ):
        return T_CLOSE
    elif ( token[ 0 ] in "'\"" ):
        return T_PHRASE
    elif ( token.lower() == 'and' ):
        return T_AND
    elif ( token.lower() == 'or' ):
        return T_OR
    elif ( token.lower() in ( 'not', '!', '-' ) ):
        return T_NOT
    elif ( token == '+' ):
        return T_PLUS
    elif ( token == '~' ):
        raise( ParseSyntaxError( "proximity searches not supported" ) )
    elif ( token == '/' ):
        raise( ParseSyntaxError( "regular expression searches not supported" ) )
    elif ( ( WILD_PLACEHOLDER in token ) and not re.match( r'^\w+' + WILD_PLACEHOLDER + '$', token ) ):
        raise( ParseSyntaxError( "* can only appear the end of a term: " + token ) )
    elif ( token == NOOP_PLACEHOLDER ):
        return T_NOOP
    elif ( token.endswith( FIELD_PLACEHOLDER ) ):
        return T_FIELD
    elif ( re.match( '^\w+$', token ) ):
        return T_TERM
    else:
        raise( ParseSyntaxError( "unrecognized token '" + str( token ) + "'" ) )

def _get_tokens( query ):
    """ get a list of Token objects from the query """

    tokens = []

    # normalize everything to lower case and make sure nothing conflicts with placeholders below
    query = query.lower()

    # the tokenizer interprets as ! as a special character, which results in the ! and subsequent text disappearing.
    # we just replace it with the equivalent - to avoid this.
    query = query.replace( '!', '-' )

    # also the tokenizer treats newlines as tokens, so we replace them
    query = query.replace( "\n", " " );
    query = query.replace( "\r", " " );

    # we can't support solr range searches, and they break the tokenizer, so just regexp them away
    query = re.sub( '\w+:\[[^\]]*\]', NOOP_PLACEHOLDER, query )

    # we want to include ':' at the end of field names, but tokenizer wants to make it a separate token
    query = re.sub( ':', FIELD_PLACEHOLDER + ' ', query )

    # we want to include '*' at the end of field names, but tokenizer wants to make it a separate token
    query = re.sub( r'\*', WILD_PLACEHOLDER , query )

    l.debug( "filtered query: " + query )

    raw_tokens = generate_tokens(io.StringIO( query ).readline )

    for raw_token in raw_tokens:
        token_value = raw_token[ 1 ]
        l.debug( "raw token '%s'" % token_value )
        if ( len( token_value ) > 0 ):
            type = _get_token_type( token_value )
            tokens.append( Token( token_value, type ) )

    return tokens


def parse( solr_query ):
    """ Parse a solr query and return a set of *Node objects that encapsulate the query in structured form."""

    solr_query = "( " + decode_string_from_bytes_if_needed( solr_query ) + " )";

    tokens = _get_tokens( solr_query )

    l.debug( tokens )

    return _parse_tokens( tokens )
