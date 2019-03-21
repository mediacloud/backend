
--
-- SimilarWeb metrics
--
CREATE TABLE similarweb_metrics (
    similarweb_metrics_id  SERIAL                   PRIMARY KEY,
    domain                 VARCHAR(1024)            NOT NULL,
    month                  DATE,
    visits                 INTEGER,
    update_date            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (domain, month)
);


--
-- Unnormalized table
--
CREATE TABLE similarweb_media_metrics (
    similarweb_media_metrics_id    SERIAL                   PRIMARY KEY,
    media_id                       INTEGER                  UNIQUE NOT NULL references media,
    similarweb_domain              VARCHAR(1024)            NOT NULL,
    domain_exact_match             BOOLEAN                  NOT NULL,
    monthly_audience               INTEGER                  NOT NULL,
    update_date                    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);



