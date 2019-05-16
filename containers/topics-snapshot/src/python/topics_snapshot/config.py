from mediawords.util.config import env_value


class TopicsSnapshotConfig(object):
    """Topic snapshot configuration."""

    @staticmethod
    def model_reps() -> int:
        """Not sure what this is."""
        return int(env_value('MC_TOPICS_SNAPSHOT_MODEL_REPS'))
