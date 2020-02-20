"""
Exceptions thrown by the Facebook Graph API client.

All exceptions derive from McFacebookException. There are two types of exceptions:

* McFacebookSoftFailureException -- a "soft" error which means that the API call failed for those particular inputs for
  whatever reason, but that the worker can continue making API calls for other inputs.

* McFacebookHardFailureException -- a "hard" error which occurs on unexpected responses, permanent API errors, etc. and
  on which the worker should stop operation as the subsequent requests are not expected to be successful.

"""

from typing import Union


class McFacebookException(Exception):
    """Generic exception."""
    pass


# ---

class McFacebookSoftFailureException(McFacebookException):
    """
    Soft exception.

    Thrown on errors that perhaps happened with this particular input.
    """
    pass


class McFacebookInvalidURLException(McFacebookSoftFailureException):
    """
    Argument URL is invalid in some way.

    It's probably just this one URL, others are likely to work, so it's a soft error
    """

    def __init__(self, url: str, error_message: str):
        super().__init__(f"Invalid URL: '{url}'; message: {error_message}")


# ---

class McFacebookHardFailureException(McFacebookException):
    """
    Hard exception.

    Thrown on unrecoverable errors on which we should probably stop operation and take a look into what's happening.
    """
    pass


class McFacebookInvalidParametersException(McFacebookHardFailureException):
    """
    Exception thrown on invalid parameters.

    If a function got passed invalid parameters, it means that the caller's code should be fixed and there's no point in
    continuing further, so it's a hard failure.
    """
    pass


class McFacebookInvalidConfigurationException(McFacebookHardFailureException):
    """
    Exception thrown on invalid configuration.

    If Facebook worker is not configured, there's no point in trying to do anything so it's a hard failure.
    """
    pass


class McFacebookUnexpectedAPIResponseException(McFacebookHardFailureException):
    """
    Exception thrown when we receive something that we didn't expect from the API.

    Thrown when we're missing keys in the response JSON that should be there, response can't be decoded from JSON, etc.
    This is something that the programmer hasn't seen before so it's a hard failure.
    """

    def __init__(self, response: Union[str, dict, list], error_message: str):
        super().__init__(f"Unexpected API response: {error_message}; response: {response}")


class McFacebookErrorAPIResponseException(McFacebookHardFailureException):
    """
    Exception thrown when Facebook API responds with an error response.

    We consider it a "hard" error as we try to make sure that all inputs to the API are valid, and for valid inputs
    Facebook API should always return something that's not an error.
    """
    pass
