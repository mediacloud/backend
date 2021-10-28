import abc

from mediawords.util.config import env_value, file_with_env_value


class MergeMediaConfig(object, metaclass=abc.ABCMeta):
