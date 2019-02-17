from jinja2 import Environment, FileSystemLoader, Template
import os
from typing import Dict

from mediawords.util.mail import Message
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McMailTemplatesException(Exception):
    """Email templates exception."""
    pass


class McMailTemplatesNotFound(McMailTemplatesException):
    """Exception thrown when one or more templates are not found."""
    pass


class TemplateMessage(Message):
    """Generate email message using Jinja2 template."""

    def __init__(self, to: str, template_basename: str, attributes: Dict[str, str]):

        to = decode_object_from_bytes_if_needed(to)

        if not to:
            raise McMailTemplatesException('"to" is not set.')

        text_template = TemplateMessage.__jinja2_template(
            template_filename='%s.txt' % template_basename,
            autoescape=False,
        )
        html_template = TemplateMessage.__jinja2_template(
            template_filename='%s.html' % template_basename,
            autoescape=True,
        )

        # Parse subject out of text template's "content_body"
        subject = TemplateMessage.__jinja2_content_title(
            template=text_template,
            attributes=attributes,
        )
        if not subject:
            raise McMailTemplatesException('Unable to extract subject from template "%s"' % template_basename)

        # Render content
        text_body = text_template.render(attributes)
        html_body = html_template.render(attributes)

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
        email_templates_path = '/usr/share/perl5/MediaWords/Util/Mail/Message/Templates/email-templates'
        if not os.path.isdir(email_templates_path):
            raise McMailTemplatesNotFound('Templates directory was not found at "%s".' % email_templates_path)
        return email_templates_path

    @staticmethod
    def __jinja2_template(template_filename: str, autoescape: bool = True) -> Template:
        """Render Jinja2 template body."""

        templates_path = TemplateMessage.__templates_path()

        if not os.path.isfile(os.path.join(templates_path, template_filename)):
            raise McMailTemplatesNotFound('Template "%s" was not found at "%s".' % (template_filename, templates_path,))

        environment = Environment(loader=FileSystemLoader(templates_path), autoescape=autoescape)
        template = environment.get_template(template_filename)
        return template

    @staticmethod
    def __jinja2_content_title(template: Template, attributes: dict) -> str:
        """Extract 'content_title' from Jinja2 template."""
        content_title_block_name = 'content_title'
        # noinspection PyUnresolvedReferences
        if content_title_block_name not in template.blocks:
            raise McMailTemplatesException('"%s" block was not found in template.')
        # noinspection PyUnresolvedReferences
        content_title_block = template.blocks[content_title_block_name]
        context = template.new_context(attributes)

        lines = []
        for line in content_title_block(context):
            if len(line):
                lines.append(line.strip())

        if not len(lines) == 1:
            raise McMailTemplatesException('"%s" spans across more than one line' % content_title_block_name)

        content_title = lines[0].strip()
        if len(content_title) == 0:
            raise McMailTemplatesException('"%s" is empty.' % content_title_block_name)

        return content_title


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


class TopicSpiderUpdateMessage(TemplateMessage):
    """Generate and return "topic spider update" email message."""

    def __init__(self, to: str, topic_name: str, topic_url: str, topic_spider_status: str):
        if not topic_name:
            raise McMailTemplatesException('"topic_name" is not set.')
        if not topic_url:
            raise McMailTemplatesException('"topic_url" is not set.')
        if not topic_spider_status:
            raise McMailTemplatesException('"topic_spider_status" is not set.')

        topic_name = decode_object_from_bytes_if_needed(topic_name)
        topic_url = decode_object_from_bytes_if_needed(topic_url)
        topic_spider_status = decode_object_from_bytes_if_needed(topic_spider_status)

        TemplateMessage.__init__(
            self=self,
            to=to,
            template_basename='topic_spider_update',
            attributes={
                'topic_name': topic_name,
                'topic_url': topic_url,
                'topic_spider_status': topic_spider_status,
            }
        )
