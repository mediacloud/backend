


--
-- CoreNLP annotations
--
CREATE TABLE corenlp_annotations (
    corenlp_annotations_id  SERIAL    PRIMARY KEY,
    object_id               INTEGER   NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    raw_data                BYTEA     NOT NULL
);
CREATE UNIQUE INDEX corenlp_annotations_object_id ON corenlp_annotations (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE corenlp_annotations
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;


--
-- Bit.ly processing results
--
CREATE TABLE bitly_processing_results (
    bitly_processing_results_id   SERIAL    PRIMARY KEY,
    object_id                     INTEGER   NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    raw_data                      BYTEA     NOT NULL
);
CREATE UNIQUE INDEX bitly_processing_results_object_id ON bitly_processing_results (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE bitly_processing_results
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;




