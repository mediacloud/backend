from mediawords.util.mail_message.templates import TemplateMessage, McMailTemplatesException
from mediawords.util.perl import decode_object_from_bytes_if_needed


class AuthActivationNeededMessage(TemplateMessage):
    """Generate and return "activation needed" email message."""

    def __init__(self, to: str, full_name: str, activation_url: str, subscribe_to_newsletter: bool):

        if not full_name:
            raise McMailTemplatesException('"full_name" is not set.')
        if not activation_url:
            raise McMailTemplatesException('"activation_url" is not set.')
        if subscribe_to_newsletter is None:
            raise McMailTemplatesException('"subscribe_to_newsletter" is not set.')

        full_name = decode_object_from_bytes_if_needed(full_name)
        activation_url = decode_object_from_bytes_if_needed(activation_url)

        TemplateMessage.__init__(
            self=self,
            to=to,
            template_basename='activation_needed',
            attributes={
                'full_name': full_name,
                'activation_url': activation_url,
                'subscribe_to_newsletter': bool(int(subscribe_to_newsletter)),
            }
        )


class AuthActivatedMessage(TemplateMessage):
    """Generate and return "activated" email message."""

    def __init__(self, to: str, full_name: str):
        if not full_name:
            raise McMailTemplatesException('"full_name" is not set.')

        full_name = decode_object_from_bytes_if_needed(full_name)

        TemplateMessage.__init__(
            self=self,
            to=to,
            template_basename='activated',
            attributes={
                'full_name': full_name,
            }
        )


class AuthResetPasswordMessage(TemplateMessage):
    """Generate and return "reset password" email message."""

    def __init__(self, to: str, full_name: str, password_reset_url: str):

        if not full_name:
            raise McMailTemplatesException('"full_name" is not set.')
        if not password_reset_url:
            raise McMailTemplatesException('"password_reset_url" is not set.')

        full_name = decode_object_from_bytes_if_needed(full_name)
        password_reset_url = decode_object_from_bytes_if_needed(password_reset_url)

        TemplateMessage.__init__(
            self=self,
            to=to,
            template_basename='reset_password_request',
            attributes={
                'full_name': full_name,
                'password_reset_url': password_reset_url,
            }
        )


class AuthPasswordChangedMessage(TemplateMessage):
    """Generate and return "password changed" email message."""

    def __init__(self, to: str, full_name: str):
        if not full_name:
            raise McMailTemplatesException('"full_name" is not set.')

        full_name = decode_object_from_bytes_if_needed(full_name)

        TemplateMessage.__init__(
            self=self,
            to=to,
            template_basename='password_changed',
            attributes={
                'full_name': full_name,
            }
        )


class AuthAPIKeyResetMessage(TemplateMessage):
    """Generate and return "password changed" email message."""

    def __init__(self, to: str, full_name: str):
        if not full_name:
            raise McMailTemplatesException('"full_name" is not set.')

        full_name = decode_object_from_bytes_if_needed(full_name)

        TemplateMessage.__init__(
            self=self,
            to=to,
            template_basename='api_key_reset',
            attributes={
                'full_name': full_name,
            }
        )
