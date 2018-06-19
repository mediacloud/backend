"""Functions for manipulating Solr queries."""

import abc
import enum
import inspect
import io
import shlex
import re

from tokenize import generate_tokens
from typing import List, Callable, Union

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McSolrQueryException(Exception):
    """Generic Solr query exception."""
    pass


class McSolrEmptyQueryException(Exception):
    """Raise when filtering a query results in an entirely empty query."""
    pass


class McSolrQueryParseSyntaxException(McSolrQueryException):
    """Error class for syntax errors encountered when parsing."""
    pass


class McSolrImplementationException(McSolrQueryException):
    """Implementation errors."""
    pass


class TokenType(enum.Enum):
    """Token types."""
    OPEN = 'open paren'
    CLOSE = 'close paren'
    PHRASE = 'phrase'
    AND = 'and'
    OR = 'or'
    NOT = 'not'
    FIELD = 'field'
    TERM = 'term'
    PLUS = 'plus'
    MINUS = 'minus'
    NOOP = 'noop'
    PROXIMITY = 'proximity'


# this text will be considered a noop token
NOOP_PLACEHOLDER = '__NOOP__'

# replace ':' with this before tokenization so that it gets included with the field name
FIELD_PLACEHOLDER = '__FIELD__'

# replace '*' with this before tokenization so that it gets included with the term
WILD_PLACEHOLDER = '__WILD__'


class Token(object):
    """Object that holds the token value and type. type should one of T_* above """

    token_type = None
    token_value = None

    def __init__(self, token_value, token_type):
        self.token_value = token_value
        self.token_type = token_type

    def __repr__(self):
        return "[ %s: %s ]" % (self.token_type, self.token_value)

    def __str__(self):
        return self.__repr__()


class AbstractParseNode(object):
    __metaclass__ = abc.ABCMeta

    field = None
    operand = None
    parent = None
    filtered_by_function = None
    operands = []

    @abc.abstractmethod
    def get_re(self, operands: list = None) -> str:
        raise NotImplementedError("Abstract method")

    @abc.abstractmethod
    def get_inclusive_re(self, operands: list = None) -> str:
        raise NotImplementedError("Abstract method")

    @abc.abstractmethod
    def get_tsquery(self) -> str:
        raise NotImplementedError("Abstract method")

    @abc.abstractmethod
    def filter_tree(self, filter_function):
        raise NotImplementedError("Abstract method")


class ParseNode(AbstractParseNode):
    """Parent class for universal methods for *Node classes."""

    @abc.abstractmethod
    def _filter_node_children(self, filter_function):
        raise NotImplementedError("Abstract method")

    @abc.abstractmethod  # further clarify parameter type of get_re()
    def get_re(self, operands: List[AbstractParseNode] = None) -> str:
        raise NotImplementedError("Abstract method")

    def get_inclusive_re(self, operands: List[AbstractParseNode] = None) -> str:
        raise NotImplementedError("Abstract method")

    @staticmethod
    def __node_is_field_or_noop(node: AbstractParseNode) -> bool:
        """Return true if the field is a non-text field or is a noop."""

        if (type(node) is FieldNode) and (node.field != 'text'):
            return True
        elif type(node) is NoopNode:
            return True

        return False

    @staticmethod
    def __node_is_field_or_noop_or_not(node: AbstractParseNode) -> bool:
        """Return true if the field is a non-text field or is a noop."""

        if (type(node) is FieldNode) and (node.field != 'text'):
            return True
        elif type(node) in (NoopNode, NotNode):
            return True

        return False

    def __str__(self):
        return self.__repr__()

    def _filter_boolean_node_children(self, filter_function: Callable[[AbstractParseNode], bool]) \
            -> Union[AbstractParseNode, None]:

        boolean_type = type(self)
        filtered_operands = []
        for operand in self.operands:
            filtered_operand = operand.filter_tree(filter_function=filter_function)
            if filtered_operand:
                filtered_operands.append(filtered_operand)

        if len(filtered_operands) > 0:
            return boolean_type(filtered_operands)
        else:
            return None

    def filter_tree(self, filter_function: Callable[[AbstractParseNode], bool]) -> Union[AbstractParseNode, None]:
        """Filter all nodes from the tree for which filter_function returns tree.

        So, if the filter is lambda x: type( x ) is NotNode then '( foo and !bar ) or baz' will be filtered to
        '( foo ) or baz'."""

        try:
            if self.filtered_by_function == filter_function:
                return self
        except AttributeError:
            pass

        if filter_function(self):
            return None
        else:
            filtered_tree = self._filter_node_children(filter_function=filter_function)
            if filtered_tree:
                filtered_tree.filtered_by_function = filter_function
            return filtered_tree

    def tsquery(self) -> str:
        """Return a postgres tsquery that represents the parse tree."""

        filtered_tree = self.filter_tree(filter_function=self.__node_is_field_or_noop)

        if filtered_tree is None:
            raise McSolrEmptyQueryException("filtered query is empty without fields or ranges")

        return filtered_tree.get_tsquery()

    def re(self, is_logogram=False) -> str:
        """Return a posix regex that represents the parse tree."""

        filtered_tree = self.filter_tree(filter_function=self.__node_is_field_or_noop_or_not)

        if filtered_tree is None:
            raise McSolrEmptyQueryException("filtered query is empty without fields or ranges")

        regexp = filtered_tree.get_re()

        # for logogram languages, remove the beginning word boundary because it breaks the re
        if is_logogram:
            regexp = regexp.replace('[[:<:]]', '')

        return regexp

    def inclusive_re(self, is_logogram=False) -> str:
        """Return a posix regex that represents the parse tree as an inclusive query, meaning
           that it converts ANDs into ORs to match any possible term in the query
        """

        filtered_tree = self.filter_tree(filter_function=self.__node_is_field_or_noop_or_not)

        if filtered_tree is None:
            raise McSolrEmptyQueryException("filtered query is empty without fields or ranges")

        regexp = filtered_tree.get_inclusive_re()

        # for logogram languages, remove the beginning word boundary because it breaks the re
        if is_logogram:
            regexp = regexp.replace('[[:<:]]', '')

        return regexp


class TermNode(ParseNode):
    """Parse node type for a simple keyword."""

    def __init__(self, term, wildcard=False, phrase=False, proximity=None):
        self.term = term
        self.wildcard = wildcard
        self.phrase = phrase
        self.proximity = proximity

    def __repr__(self):
        return self.term if (not self.wildcard) else self.term + "*"

    def get_tsquery(self) -> str:
        if self.phrase:
            dequoted_phrase = shlex.split(self.term)[0]
            operands = []
            for term in re.split('\W+', dequoted_phrase):
                if term:
                    operands.append(TermNode(term))

            if len(operands) == 0:
                raise McSolrQueryParseSyntaxException("empty phrase not allowed")

            return AndNode(operands).get_tsquery()
        else:
            return self.term if (not self.wildcard) else self.term + ":*"

    def get_re(self, operands: List[AbstractParseNode] = None, inclusive: bool = False) -> str:
        term = self.term

        if self.phrase:
            term = shlex.split(term)[0]

            # ignore wildcards, since the regex ignores the end of the word anyway
            term = re.sub(re.escape(WILD_PLACEHOLDER), '', term)

            # should already be lower case, but make sure
            term = term.lower()

            space_place_holder = 'SPACEPLACEHOLDER'
            # replace spaces with placeholder text so that we can replace it with [[:space:]] after the re.sub below
            term = re.sub(r'\s+', space_place_holder, term)

            # escape special characters.  re.escape() escapes everything that is not
            # ascii alnum, which confuses the postgres reg ex engine
            term = re.sub(r"\W", r"\\\g<0>", term)

            if inclusive:
                words = term.split(space_place_holder)
                return OrNode(list(map(lambda x: TermNode(x), words))).get_re()
            elif self.proximity is None:
                term = re.sub(space_place_holder, '[[:space:]]+', term)
                return '[[:<:]]' + term
            else:
                # proximity searches do not care about order, so we need to change this to an and node, which will
                # generate the and regex permutations. we are just ignoring the actual proximity here for simplicity.
                words = term.split(space_place_holder)
                return AndNode(list(map(lambda x: TermNode(x), words))).get_re()
        elif term == '':
            return '.*'
        else:
            # escape special characters.  re.escape() escapes everything that is not
            # ascii alnum, which confuses the postgres reg ex engine
            term = '[[:<:]]' + re.sub(r"\W", r"\\\g<0>", term)
            return term

    def get_inclusive_re(self, operands: List[AbstractParseNode] = None) -> str:
        return self.get_re(operands, inclusive=True)

    def _filter_node_children(self, filter_function: Callable[[AbstractParseNode], bool]) \
            -> Union[AbstractParseNode, None]:
        return TermNode(self.term, wildcard=self.wildcard, phrase=self.phrase, proximity=self.proximity)


class BooleanNode(ParseNode):
    """Super class for ANDs and ORs."""

    __metaclass__ = abc.ABCMeta

    def __init__(self, operands):
        self.operands = operands
        for operand in operands:
            operand.parent = self

    @abc.abstractmethod
    def _plain_connector(self):
        raise NotImplementedError("sub class must define _plain_connector")

    @abc.abstractmethod
    def _tsquery_connector(self):
        raise NotImplementedError("sub class must define _tsquery_connector")

    def __repr__(self):
        connector = ' ' + self._plain_connector() + ' '
        return '( ' + connector.join(map(lambda x: str(x), self.operands)) + ' )'

    def get_tsquery(self) -> str:
        connector = ' ' + self._tsquery_connector() + ' '
        return '( ' + connector.join(map(lambda x: x.get_tsquery(), self.operands)) + ' )'

    def get_re(self, operands: List[AbstractParseNode] = None) -> str:
        raise NotImplementedError("FIXME not implemented!")

    def get_inclusive_re(self, operands: List[AbstractParseNode] = None) -> str:
        raise NotImplementedError("FIXME not implemented!")

    def _filter_node_children(self, filter_function: Callable[[AbstractParseNode], bool]) \
            -> Union[AbstractParseNode, None]:
        return self._filter_boolean_node_children(filter_function=filter_function)


class AndNode(BooleanNode):
    """Parse node for an AND clause."""

    def _plain_connector(self):
        return 'and'

    def _tsquery_connector(self):
        return '&'

    def get_re(self, operands: List[AbstractParseNode] = None) -> str:
        if operands is None:
            operands = self.operands

        if len(operands) == 1:
            return operands[0].get_re()
        else:
            a = operands[0].get_re()
            b = self.get_re(operands=operands[1:])
            return '(?: (?: %s .* %s ) | (?: %s .* %s ) )' % (a, b, b, a)

    def get_inclusive_re(self, operands: List[AbstractParseNode] = None) -> str:
        return OrNode(self.operands).get_inclusive_re()


class OrNode(BooleanNode):
    """Parse node for an OR clause."""

    def _plain_connector(self):
        return 'or'

    def _tsquery_connector(self):
        return '|'

    def get_re(self, operands: List[AbstractParseNode] = None) -> str:
        return '(?: ' + ' | '.join(map(lambda x: x.get_re(), self.operands)) + ' )'

    def get_inclusive_re(self, operands: List[AbstractParseNode] = None) -> str:
        return '(?: ' + ' | '.join(map(lambda x: x.get_inclusive_re(), self.operands)) + ' )'


class NotNode(ParseNode):
    """Parse node for a NOT clause."""

    def __init__(self, operand: AbstractParseNode):
        self.operand = operand
        operand.parent = self

    def __repr__(self):
        return '!' + str(self.operand)

    def get_tsquery(self) -> str:
        return '!' + self.operand.get_tsquery()

    def get_re(self, operands: List[AbstractParseNode] = None) -> str:
        raise McSolrQueryParseSyntaxException("not operations not supported for re()")

    def get_inclusive_re(self, operands: List[AbstractParseNode] = None) -> str:
        raise McSolrQueryParseSyntaxException("not operations not supported for inclusive_re()")

    def _filter_node_children(self, filter_function: Callable[[AbstractParseNode], bool]) \
            -> Union[AbstractParseNode, None]:
        filtered_operand = self.operand.filter_tree(filter_function=filter_function)
        return NotNode(operand=filtered_operand) if filtered_operand else None


class FieldNode(ParseNode):
    """Parse node for a field clause."""

    def __init__(self, field: str, operand: AbstractParseNode):
        self.field = field
        self.operand = operand
        operand.parent = self

    def __repr__(self):
        return self.field + ':' + str(self.operand)

    def get_tsquery(self) -> str:
        if self.field == 'text':
            return self.operand.get_tsquery()
        else:
            raise McSolrImplementationException("non-text field nodes should have been filtered")

    def get_re(self, operands: List[AbstractParseNode] = None) -> str:
        if self.field == 'text':
            return self.operand.get_re()
        else:
            raise McSolrImplementationException("non-text field nodes should have been filtered")

    def get_inclusive_re(self, operands: List[AbstractParseNode] = None) -> str:
        if self.field == 'text':
            return self.operand.get_inclusive_re()
        else:
            raise McSolrImplementationException("non-text field nodes should have been filtered")

    def _filter_node_children(self, filter_function: Callable[[AbstractParseNode], bool]) \
            -> Union[AbstractParseNode, None]:
        filtered_operand = self.operand.filter_tree(filter_function=filter_function)
        if filtered_operand:
            return FieldNode(field=self.field, operand=filtered_operand)
        else:
            return None


class NoopNode(ParseNode):
    """Parse node for a node that should have no impact on the result of the query."""

    def __init__(self):
        pass

    def __repr__(self):
        return NOOP_PLACEHOLDER

    def get_tsquery(self) -> str:
        raise McSolrImplementationException("noop nodes should have been filtered")

    def get_re(self, operands: List[AbstractParseNode] = None) -> str:
        raise McSolrImplementationException("noop nodes should have been filtered")

    def get_inclusive_re(self, operands: List[AbstractParseNode] = None) -> str:
        raise McSolrImplementationException("noop nodes should have been filtered")

    def _filter_node_children(self, filter_function: Callable[[AbstractParseNode], bool]) \
            -> Union[AbstractParseNode, None]:
        return NoopNode()


def __check_type(checked_token: Token, checked_want_type: List[TokenType]) -> None:
    """Throw a McSolrQueryParseSyntaxException if the given type is not in the want_type list."""
    if checked_token.token_type not in checked_want_type:
        raise McSolrQueryParseSyntaxException(
            "Token '%s' is not one of the following expected types: %s" % (
                str(checked_token), str(checked_want_type))
        )


def __parse_tokens(tokens: List[Token], want_type: List[TokenType] = None) -> ParseNode:
    """Given a flat list of tokens, generate a boolean logic tree."""

    log.debug("parse tree: " + str(tokens))

    if want_type is None:
        want_type = [TokenType.OPEN, TokenType.PHRASE, TokenType.NOT, TokenType.TERM]

    clause = None
    boolean_clause = None
    hanging_boolean = False

    while len(tokens) > 0:

        frame_depth = len(inspect.getouterframes(inspect.currentframe()))
        log.debug("clause: %s [%s] [frame_depth: %s]" % (clause, type(clause), frame_depth))

        token = tokens.pop(0)
        log.debug("parse token: " + str(token))

        if (token.token_type == TokenType.PLUS) and (not clause or (type(clause) in (AndNode, OrNode))):
            continue

        if hanging_boolean:
            boolean_clause = clause
            hanging_boolean = False
        elif clause and (token.token_type in [TokenType.OPEN,
                                              TokenType.PHRASE,
                                              TokenType.TERM,
                                              TokenType.NOOP,
                                              TokenType.FIELD]):
            log.debug("INSERT OR")
            tokens.insert(0, token)
            token = Token(token_type=TokenType.OR, token_value='or')
        elif clause and (token.token_type in [TokenType.NOT]):
            log.debug("INSERT AND")
            tokens.insert(0, token)
            token = Token(token_type=TokenType.AND, token_value='and')

        __check_type(token, want_type)

        if token.token_type == TokenType.OPEN:
            clause = __parse_tokens(
                tokens=tokens,
                want_type=[
                    TokenType.OPEN,
                    TokenType.PHRASE,
                    TokenType.NOT,
                    TokenType.FIELD,
                    TokenType.TERM,
                    TokenType.NOOP,
                    TokenType.CLOSE
                ]
            )
            want_type = [
                TokenType.OPEN,
                TokenType.PHRASE,
                TokenType.NOT,
                TokenType.FIELD,
                TokenType.TERM,
                TokenType.NOOP,
                TokenType.CLOSE,
                TokenType.AND,
                TokenType.OR,
                TokenType.PLUS
            ]

        elif token.token_type == TokenType.CLOSE:
            break

        elif token.token_type == TokenType.NOOP:
            want_type = [TokenType.CLOSE, TokenType.AND, TokenType.OR, TokenType.PLUS]
            clause = NoopNode()

        elif token.token_type == TokenType.TERM:
            want_type = [TokenType.CLOSE, TokenType.AND, TokenType.OR, TokenType.PLUS]
            wildcard = False
            if token.token_value.endswith(WILD_PLACEHOLDER):
                token.token_value = token.token_value.replace(WILD_PLACEHOLDER, '')
                wildcard = True

            clause = TermNode(token.token_value, wildcard=wildcard)

        elif token.token_type == TokenType.PHRASE:
            want_type = [TokenType.CLOSE, TokenType.AND, TokenType.OR, TokenType.PLUS]

            if ((len(tokens) >= 2) and
                    (tokens[0].token_type == TokenType.PROXIMITY) and
                    (tokens[1].token_type == TokenType.TERM) and
                    (re.search('^\d+$', tokens[1].token_value))):
                tokens.pop(0)
                distance_token = tokens.pop(0)
                clause = TermNode(token.token_value, phrase=True, proximity=int(distance_token.token_value))
            else:
                clause = TermNode(token.token_value, phrase=True)

        elif token.token_type in (TokenType.AND, TokenType.PLUS, TokenType.OR):
            want_type = [
                TokenType.OPEN,
                TokenType.PHRASE,
                TokenType.NOT,
                TokenType.FIELD,
                TokenType.TERM,
                TokenType.NOOP,
                TokenType.CLOSE,
                TokenType.PLUS
            ]

            node_type = OrNode if (token.token_type == TokenType.OR) else AndNode

            if type(clause) is node_type:
                clause = node_type(clause.operands)
            else:
                clause = node_type([clause])

            hanging_boolean = True

        elif token.token_type == TokenType.FIELD:
            want_type = [TokenType.CLOSE, TokenType.AND, TokenType.OR, TokenType.PLUS]
            field_name = re.sub(FIELD_PLACEHOLDER, '', token.token_value)
            next_token = tokens.pop(0)
            if next_token.token_type == TokenType.OPEN:
                field_clause = __parse_tokens(
                    tokens=tokens,
                    want_type=[
                        TokenType.PHRASE,
                        TokenType.NOT,
                        TokenType.TERM,
                        TokenType.NOOP,
                        TokenType.CLOSE,
                        TokenType.PLUS
                    ]
                )
            else:
                field_clause = __parse_tokens(tokens=[next_token], want_type=[
                    TokenType.PHRASE,
                    TokenType.TERM,
                    TokenType.NOOP
                ])

            log.debug("field operand for %s: %s" % (field_name, field_clause))

            clause = FieldNode(field_name, field_clause)

        elif token.token_type == TokenType.NOT:
            want_type = [TokenType.CLOSE, TokenType.AND, TokenType.OR, TokenType.PLUS]
            # operand = None
            next_token = tokens.pop(0)
            if next_token.token_type == TokenType.OPEN:
                operand = __parse_tokens(tokens=tokens, want_type=[
                    TokenType.FIELD,
                    TokenType.PHRASE,
                    TokenType.NOT,
                    TokenType.TERM,
                    TokenType.NOOP,
                    TokenType.CLOSE,
                    TokenType.PLUS
                ])
            elif next_token.token_type == TokenType.FIELD:
                tokens.insert(0, next_token)
                operand = __parse_tokens(tokens=tokens, want_type=[TokenType.FIELD])
            else:
                operand = __parse_tokens(tokens=[next_token], want_type=[
                    TokenType.PHRASE,
                    TokenType.TERM,
                    TokenType.NOOP,
                    TokenType.FIELD
                ])
            clause = NotNode(operand)

        else:
            raise McSolrQueryParseSyntaxException("unknown type for token '%s'" % token)

        want_type += [TokenType.CLOSE]

        if boolean_clause:
            log.debug("boolean append: %s <- %s" % (boolean_clause, clause))
            if type(boolean_clause) is type(clause):
                boolean_clause.operands += clause.operands
            else:
                boolean_clause.operands.append(clause)
            clause = boolean_clause
            boolean_clause = None

    # noinspection PyBroadException
    try:
        log.debug("parse result: " + str(clause))
    except:  # noqa
        log.debug("parse_result: [" + str(type(clause)) + "]")

    return clause


def __get_token_type(token: str) -> TokenType:
    """Given some token text, return one of T_* as the type for that token."""

    if token == '(':
        return TokenType.OPEN
    elif token == ')':
        return TokenType.CLOSE
    elif token[0] in "'\"":
        return TokenType.PHRASE
    elif token.lower() == 'and':
        return TokenType.AND
    elif token.lower() == 'or':
        return TokenType.OR
    elif token.lower() in ('not', '!', '-'):
        return TokenType.NOT
    elif token == '+':
        return TokenType.PLUS
    elif token == '~':
        return TokenType.PROXIMITY
    elif token == '/':
        raise McSolrQueryParseSyntaxException("regular expression searches not supported")
    elif token == WILD_PLACEHOLDER:
        return TokenType.TERM
    elif (WILD_PLACEHOLDER in token) and not re.match(r'^\w+' + WILD_PLACEHOLDER + '$', token):
        raise McSolrQueryParseSyntaxException("* can only appear by itself or at the end of a term: " + token)
    elif token == NOOP_PLACEHOLDER:
        return TokenType.NOOP
    elif token.endswith(FIELD_PLACEHOLDER):
        return TokenType.FIELD
    elif re.match('^\w+$', token):
        return TokenType.TERM
    else:
        raise McSolrQueryParseSyntaxException("unrecognized token '%s'" % str(token))


def __get_tokens(query: str) -> List[Token]:
    """Get a list of Token objects from the query."""

    tokens = []

    # normalize everything to lower case and make sure nothing conflicts with placeholders below
    query = query.lower()

    # remove {!complexphrase foo=bar} type solr qualifiers
    query = re.sub('\{\![^\}]*\}', '', query)

    # the tokenizer interprets as ! as a special character, which results in the ! and subsequent text disappearing.
    # we just replace it with the equivalent - to avoid this.
    query = query.replace('!', '-')

    # also the tokenizer treats newlines as tokens, so we replace them
    query = query.replace("\n", " ")
    query = query.replace("\r", " ")

    # we can't support solr range searches, and they break the tokenizer, so just regexp them away
    query = re.sub('\w+:\[[^\]]*\]', NOOP_PLACEHOLDER, query)

    # we want to include ':' at the end of field names, but tokenizer wants to make it a separate token
    query = re.sub(':', FIELD_PLACEHOLDER + ' ', query)

    # we want to include '*' at the end of field names, but tokenizer wants to make it a separate token
    query = re.sub(r'\*', WILD_PLACEHOLDER, query)

    log.debug("filtered query: " + query)

    raw_tokens = generate_tokens(readline=io.StringIO(query).readline)

    for raw_token in raw_tokens:
        token_value = raw_token[1]
        log.debug("raw token '%s'" % token_value)
        if len(token_value) > 0:
            token_type = __get_token_type(token=token_value)
            tokens.append(Token(token_value=token_value, token_type=token_type))

    return tokens


def parse(solr_query: str) -> ParseNode:
    """ Parse a solr query and return a set of *Node objects that encapsulate the query in structured form."""

    solr_query = "( " + decode_object_from_bytes_if_needed(solr_query) + " )"

    tokens = __get_tokens(query=solr_query)

    log.debug("Tokens: %s" % str(tokens))

    return __parse_tokens(tokens=tokens)
