from typing import Dict

from jinja2 import Environment, FileSystemLoader
import os

from mediawords.util.mail import Message
from mediawords.util.paths import mc_root_path
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McMailTemplatesException(Exception):
    """Email templates exception."""
    pass


class McMailTemplatesNotFound(McMailTemplatesException):
    """Exception thrown when one or more templates are not found."""
    pass


class TemplateMessage(Message):
    """Generate email message using Jinja2 template."""

    def __init__(self, to: str, subject: str, template_basename: str, attributes: Dict[str, str]):

        to = decode_object_from_bytes_if_needed(to)
        subject = decode_object_from_bytes_if_needed(subject)

        if not to:
            raise McMailTemplatesException('"to" is not set.')
        if not subject:
            raise McMailTemplatesException('"subject" is not set.')

        text_body = TemplateMessage.__jinja2_render(
            template_filename='%s.txt' % template_basename,
            attributes=attributes,
            autoescape=False,
        )
        html_body = TemplateMessage.__jinja2_render(
            template_filename='%s.html' % template_basename,
            attributes=attributes,
            autoescape=True,
        )

        Message.__init__(
            self=self,
            to=to,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
        )

    @staticmethod
    def __templates_path() -> str:
        """Return path to Jinja2 email templates."""
        root_path = mc_root_path()
        email_templates_path = os.path.join(
            root_path, 'lib', 'MediaWords', 'Util', 'Mail', 'Message', 'templates', 'email-templates'
        )
        if not os.path.isdir(email_templates_path):
            raise McMailTemplatesNotFound('Templates directory was not found at "%s".' % email_templates_path)
        return email_templates_path

    @staticmethod
    def __jinja2_render(template_filename: str, attributes: dict, autoescape: bool = True) -> str:
        """Render Jinja2 template."""

        templates_path = TemplateMessage.__templates_path()

        if not os.path.isfile(os.path.join(templates_path, template_filename)):
            raise McMailTemplatesNotFound('Template "%s" was not found at "%s".' % (template_filename, templates_path,))

        environment = Environment(loader=FileSystemLoader(templates_path), autoescape=autoescape)
        template = environment.get_template(template_filename)
        return template.render(attributes)


class AuthActivationNeededMessage(TemplateMessage):
    """Generate and return "activation needed" email message."""

    __EMAIL_SUBJECT = 'Activate your account'

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
            subject=self.__EMAIL_SUBJECT,
            template_basename='activation_needed',
            attributes={
                'full_name': full_name,
                'activation_url': activation_url,
                'subscribe_to_newsletter': bool(subscribe_to_newsletter),
            }
        )


class AuthActivatedMessage(TemplateMessage):
    """Generate and return "activated" email message."""

    __EMAIL_SUBJECT = 'Activated!'

    def __init__(self, to: str, full_name: str):
        if not full_name:
            raise McMailTemplatesException('"full_name" is not set.')

        full_name = decode_object_from_bytes_if_needed(full_name)

        TemplateMessage.__init__(
            self=self,
            to=to,
            subject=self.__EMAIL_SUBJECT,
            template_basename='activated',
            attributes={
                'full_name': full_name,
            }
        )


class AuthResetPasswordMessage(TemplateMessage):
    """Generate and return "reset password" email message."""

    __EMAIL_SUBJECT = 'Reset your password'

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
            subject=self.__EMAIL_SUBJECT,
            template_basename='reset_password_request',
            attributes={
                'full_name': full_name,
                'password_reset_url': password_reset_url,
            }
        )


class AuthPasswordChangedMessage(TemplateMessage):
    """Generate and return "password changed" email message."""

    __EMAIL_SUBJECT = 'Password changed!'

    def __init__(self, to: str, full_name: str):
        if not full_name:
            raise McMailTemplatesException('"full_name" is not set.')

        full_name = decode_object_from_bytes_if_needed(full_name)

        TemplateMessage.__init__(
            self=self,
            to=to,
            subject=self.__EMAIL_SUBJECT,
            template_basename='password_changed',
            attributes={
                'full_name': full_name,
            }
        )


class AuthAPIKeyResetMessage(TemplateMessage):
    """Generate and return "password changed" email message."""

    __EMAIL_SUBJECT = 'API key reset!'

    def __init__(self, to: str, full_name: str):
        if not full_name:
            raise McMailTemplatesException('"full_name" is not set.')

        full_name = decode_object_from_bytes_if_needed(full_name)

        TemplateMessage.__init__(
            self=self,
            to=to,
            subject=self.__EMAIL_SUBJECT,
            template_basename='api_key_reset',
            attributes={
                'full_name': full_name,
            }
        )
