from mediawords.util.config import env_value_or_raise


class SnapshotConfig(object):
    """Topic snapshot configuration."""

    @staticmethod
    def model_reps() -> int:
        """Not sure what this is."""
        return int(env_value('MC_TOPICS_SNAPSHOT_MODEL_REPS'))
