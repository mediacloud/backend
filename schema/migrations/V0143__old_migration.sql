


--
-- Snapshot word2vec models
--
CREATE TABLE snap.word2vec_models (
    word2vec_models_id  SERIAL      PRIMARY KEY,
    object_id           INTEGER     NOT NULL REFERENCES snapshots (snapshots_id) ON DELETE CASCADE,
    creation_date       TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- We'll need to find the latest word2vec model
CREATE INDEX snap_word2vec_models_object_id_creation_date ON snap.word2vec_models (object_id, creation_date);

CREATE TABLE snap.word2vec_models_data (
    word2vec_models_data_id SERIAL      PRIMARY KEY,
    object_id               INTEGER     NOT NULL
                                            REFERENCES snap.word2vec_models (word2vec_models_id)
                                            ON DELETE CASCADE,
    raw_data                BYTEA       NOT NULL
);
CREATE UNIQUE INDEX snap_word2vec_models_data_object_id ON snap.word2vec_models_data (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE snap.word2vec_models_data
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;




