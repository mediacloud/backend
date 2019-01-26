from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import os
import smtplib
from typing import List, Optional, Union

from mediawords.util.config.common import CommonConfig
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.log import create_logger

log = create_logger(__name__)

# Environment variable that, when set, will prevent the package from actually sending the email
__ENV_MAIL_DO_NO_SEND = 'MEDIACLOUD_MAIL_DO_NOT_SEND'


class McSendEmailException(Exception):
    """send_email() exception."""
    pass


def enable_test_mode():
    os.environ[__ENV_MAIL_DO_NO_SEND] = '1'


def disable_test_mode():
    del os.environ[__ENV_MAIL_DO_NO_SEND]


def test_mode_is_enabled() -> bool:
    return __ENV_MAIL_DO_NO_SEND in os.environ


class Message(object):
    """Email message to send."""

    from_ = None  # note the underscore
    to = []
    cc = []
    bcc = []
    subject = None
    text_body = None
    html_body = None

    def __init__(self,
                 to: Union[str, List[str]],
                 subject: str,
                 text_body: str,
                 html_body: Optional[str] = None,
                 cc: Optional[Union[str, List[str]]] = None,
                 bcc: Optional[Union[str, List[str]]] = None):
        """Email message constructor."""

        self.from_ = CommonConfig.email_from_address()

        self.subject = decode_object_from_bytes_if_needed(subject)
        self.text_body = decode_object_from_bytes_if_needed(text_body)
        self.html_body = decode_object_from_bytes_if_needed(html_body)

        self.to = decode_object_from_bytes_if_needed(to)
        if isinstance(self.to, str):
            self.to = [self.to]

        self.cc = decode_object_from_bytes_if_needed(cc)
        if isinstance(self.cc, str):
            self.cc = [self.cc]

        self.bcc = decode_object_from_bytes_if_needed(bcc)
        if isinstance(self.bcc, str):
            self.bcc = [self.bcc]


def send_email(message: Message) -> bool:
    """Send email to someone.

    Returns True on success, False on failure.

    Raises on programming error."""

    if message is None:
        raise McSendEmailException('Message is None.')

    if not message.from_:
        raise McSendEmailException("'from' is unset.")
    if message.to and (not isinstance(message.to, list)):
        raise McSendEmailException("'to' is not a list.")
    if message.cc and (not isinstance(message.cc, list)):
        raise McSendEmailException("'cc' is not a list.")
    if message.bcc and (not isinstance(message.bcc, list)):
        raise McSendEmailException("'bcc' is not a list.")

    if not (len(message.to) > 0 or len(message.cc) > 0 or len(message.bcc) > 0):
        raise McSendEmailException("No one to send the email to.")

    if not message.subject:
        raise McSendEmailException("'subject' is unset.")

    if not (message.text_body or message.html_body):
        raise McSendEmailException("No message body.")

    try:

        # Create message
        mime_message = MIMEMultipart('alternative')
        mime_message['Subject'] = '[Media Cloud] %s' % message.subject
        mime_message['From'] = message.from_
        if message.to:
            mime_message['To'] = ', '.join(message.to)
        else:
            mime_message['To'] = 'undisclosed recipients'
        if message.cc:
            mime_message['Cc'] = ', '.join(message.cc)
        if message.bcc:
            mime_message['Bcc'] = ', '.join(message.bcc)

        if message.text_body:
            message_part = MIMEText(message.text_body, 'plain', 'utf-8')
            mime_message.attach(message_part)

        # HTML gets attached last, thus making it a preferred part as per RFC
        if message.html_body:
            message_part = MIMEText(message.html_body, 'html', 'utf-8')
            mime_message.attach(message_part)

        if test_mode_is_enabled():
            log.info("Test mode is enabled, not actually sending any email.")
            log.debug("Omitted email:\n\n%s" % mime_message.as_string())

        else:

            # Connect to SMTP
            smtp = smtplib.SMTP(
                host=CommonConfig.smtp().hostname(),
                port=CommonConfig.smtp().port(),
            )

            # Send message
            refused_recipients = smtp.sendmail(mime_message['From'], mime_message['To'], mime_message.as_string())
            if len(refused_recipients):
                log.warning("Unable to send email to the following recipients: %s" % str(refused_recipients))

            smtp.quit()

    except Exception as ex:
        log.warning('Unable to send email to %s: %s' % (message.to, str(ex)))
        return False

    return True


def send_text_email(to: str, subject: str, body: str) -> bool:
    """Send plain text email to someone.

    Returns True on success, False on failure.

    Raises on programming error."""

    to = decode_object_from_bytes_if_needed(to)
    subject = decode_object_from_bytes_if_needed(subject)
    body = decode_object_from_bytes_if_needed(body)

    message = Message(to=to, subject=subject, text_body=body)
    return send_email(message)
