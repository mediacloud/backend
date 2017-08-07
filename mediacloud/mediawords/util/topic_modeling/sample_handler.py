import os
import ast

from mediawords.util.paths import mc_root_path


class SampleHandler:
    """
    Mimic the behaviour of database handler, handles access to the sample file instead.
    """
    _SAMPLE_STORIES \
        = os.path.join(mc_root_path(),
                       "mediacloud/mediawords/util/topic_modeling/sample_stories.txt")

    def query(self):
        """
        mimics the behaviour of database query, except no query command is needed
        :return: the sample data, which mimics the content of database
        """
        with open(self._SAMPLE_STORIES) as sample_file:
            lines = sample_file.readlines()[0]

        return ast.literal_eval(lines)
