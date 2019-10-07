# Sending mail

Apps can send mail using one of the pre-configured ways to do so:

* Using `sendmail` utility which is configured to relay mail to a local instance of Postfix; or
* Connecting to SMTP server using credentials provided by `SMTPConfig` configuration class; or
* Using `mail-postfix-server:25` SMTP server directly.
