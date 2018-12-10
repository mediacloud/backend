from mediawords.util.config import env_value_or_raise


class WebAppConfig(object):
    """Web application configuration."""

    @staticmethod
    def session_expires() -> int:
        """Session expiration, in seconds."""
        return 3600

    @staticmethod
    def show_stack_traces() -> bool:
        """Whether to show stack traces to the user on exceptions; might leak private data!"""
        return bool(int(env_value_or_raise('MC_WEBAPP_ALWAYS_SHOW_STACK_TRACES', allow_empty_string=True)))

    @staticmethod
    def recaptcha_public_key() -> str:
        """reCAPTCHA public key."""
        return env_value_or_raise('MC_WEBAPP_RECAPTCHA_PUBLIC_KEY', allow_empty_string=True)

    @staticmethod
    def recaptcha_private_key() -> str:
        """reCAPTCHA private key."""
        return env_value_or_raise('MC_WEBAPP_RECAPTCHA_PRIVATE_KEY', allow_empty_string=True)

    @staticmethod
    def google_analytics_account_id() -> str:
        """Google Analytics account ID."""
        return env_value_or_raise('MC_WEBAPP_GOOGLE_ANALYTICS_ACCOUNT_ID', allow_empty_string=True)

    @staticmethod
    def google_analytics_domain_name() -> str:
        """Google Analytics domain name."""
        return env_value_or_raise('MC_WEBAPP_GOOGLE_ANALYTICS_DOMAIN_NAME', allow_empty_string=True)

