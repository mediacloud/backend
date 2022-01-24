from mediawords.db import DatabaseHandler
from mediawords.util.compress import gzip, gunzip
from mediawords.util.log import create_logger

from word2vec_generate_snapshot_model import McWord2vecException

log = create_logger(__name__)


class SnapshotDatabaseModelStore(object):
    __slots__ = [
        '__db',
        '__topics_id',
        '__snapshots_id',
    ]

    def __init__(self, db: DatabaseHandler, topics_id: int, snapshots_id: int):
        self.__db = db
        self.__topics_id = topics_id
        self.__snapshots_id = snapshots_id

    def store_model(self, model_data: bytes) -> int:
        compressed_model_data = gzip(model_data)

        models_id = self.__db.query("""
            INSERT INTO snap.word2vec_models (topics_id, snapshots_id, raw_data)
            VALUES (%(topics_id)s, %(snapshots_id)s, %(raw_data)s)
            RETURNING snap_word2vec_models_id
        """, {
            'topics_id': self.__topics_id,
            'snapshots_id': self.__snapshots_id,
            'raw_data': compressed_model_data,
        }).flat()[0]

        return models_id

    def read_model(self, models_id: int) -> bytes:
        model = self.__db.select(
            table='snap.word2vec_models',
            what_to_select='raw_data',
            condition_hash={
                'topics_id': self.__topics_id,
                'snapshots_id': self.__snapshots_id,
                'snap_word2vec_models_id': models_id,
            }
        ).hash()
        if not model:
            raise McWord2vecException(
                f"Model {models_id} for topic {self.__topics_id}, snapshot {self.__snapshots_id} was not found"
            )

        compressed_model_data = model['raw_data']

        if isinstance(compressed_model_data, memoryview):
            compressed_model_data = compressed_model_data.tobytes()

        model_data = gunzip(compressed_model_data)

        return model_data
