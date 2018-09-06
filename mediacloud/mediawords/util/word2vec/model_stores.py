import abc

from mediawords.db import DatabaseHandler
from mediawords.key_value_store import KeyValueStore
from mediawords.key_value_store.postgresql import PostgreSQLStore
from mediawords.util.log import create_logger
from mediawords.util.word2vec import McWord2vecException

log = create_logger(__name__)


class AbstractModelStore(object, metaclass=abc.ABCMeta):
    """Abstract class for defining how to store generated word2vec models."""

    @abc.abstractmethod
    def store_model(self, model_data: bytes) -> int:
        """Store model data to the store.

        :param model_data: Raw serialized model data to be stored
        :return ID of a model that was just stored
        """
        raise NotImplemented("Abstract method.")

    @abc.abstractmethod
    def read_model(self, models_id: int) -> bytes:
        """Read model data from the store.

        :param models_id: Model ID to load
        :return Raw serialized model data that was read from the store
        """
        raise NotImplemented("Abstract method.")


class AbstractDatabaseModelStore(AbstractModelStore, metaclass=abc.ABCMeta):
    """Class for storing model in a database."""

    __slots__ = [
        '__db',
        '__object_id',
    ]

    @abc.abstractmethod
    def model_table(self) -> str:
        """Return table name for word2vec model metadata."""
        raise NotImplemented("Abstract method.")

    @abc.abstractmethod
    def data_table(self) -> str:
        """Return table name for word2vec model raw data."""
        raise NotImplemented("Abstract method.")

    def __init__(self, db: DatabaseHandler, object_id: int):
        """Constructor.

        :param db: Database handler
        :param object_id: Object ID (e.g. topic ID or snapshot ID) under which the model will be stored in the database
        """
        self.__db = db
        self.__object_id = object_id

    def __key_value_store(self) -> KeyValueStore:
        """Return key-value store for storing raw serialized model data."""
        return PostgreSQLStore(table=self.data_table())

    def store_model(self, model_data: bytes) -> int:
        self.__db.begin()

        primary_key_column = self.__db.primary_key_column(self.model_table())

        # Write model record
        model_metadata = self.__db.create(table=self.model_table(), insert_hash={'object_id': self.__object_id})
        models_id = model_metadata[primary_key_column]

        # Write model data
        self.__key_value_store().store_content(db=self.__db, object_id=models_id, content=model_data)

        self.__db.commit()

        return models_id

    def read_model(self, models_id: int) -> bytes:
        self.__db.begin()

        primary_key_column = self.__db.primary_key_column(self.model_table())

        model_metadata = self.__db.select(
            table=self.model_table(),
            what_to_select='*',
            condition_hash={
                'object_id': self.__object_id,
                primary_key_column: models_id,
            }
        ).hash()
        if not model_metadata:
            raise McWord2vecException("Model with object ID %d was not found." % self.__object_id)

        model_data = self.__key_value_store().fetch_content(db=self.__db, object_id=models_id)

        self.__db.commit()

        return model_data


class SnapshotDatabaseModelStore(AbstractDatabaseModelStore):
    """Database model storage for storing snapshot word2vec models."""

    def __init__(self, db: DatabaseHandler, snapshots_id: int):
        """Constructor.

        :param db: Database handler
        :param snapshots_id: Snapshot ID
        """
        super().__init__(db=db, object_id=snapshots_id)

    def model_table(self) -> str:
        return 'snap.word2vec_models'

    def data_table(self) -> str:
        return 'snap.word2vec_models_data'
