--
-- Domains for which we have SimilarWeb stats
--
CREATE TABLE similarweb_domains (
    similarweb_domains_id SERIAL PRIMARY KEY,

    -- Top-level (e.g. cnn.com) or second-level (e.g. edition.cnn.com) domain
    domain TEXT NOT NULL

);

CREATE UNIQUE INDEX similarweb_domains_domain
    ON similarweb_domains (domain);


--
-- Media - SimilarWeb domain map
--
CREATE TABLE media_similarweb_domains_map (
    media_similarweb_domains_map_id SERIAL  PRIMARY KEY,

    media_id                        INT     NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    similarweb_domains_id           INT     NOT NULL REFERENCES similarweb_domains (similarweb_domains_id) ON DELETE CASCADE
);

-- Different media sources can point to the same domain
CREATE UNIQUE INDEX media_similarweb_domains_map_media_id_sdi
    ON media_similarweb_domains_map (media_id, similarweb_domains_id);


--
-- SimilarWeb estimated visits for domain
-- (https://www.similarweb.com/corp/developer/estimated_visits_api)
--
CREATE TABLE similarweb_estimated_visits (
    similarweb_estimated_visits_id  SERIAL  PRIMARY KEY,

    -- Domain for which the stats were fetched
    similarweb_domains_id           INT     NOT NULL REFERENCES similarweb_domains (similarweb_domains_id) ON DELETE CASCADE,

    -- Month, e.g. 2018-03-01 for March of 2018
    month                           DATE    NOT NULL,

    -- Visit count is for the main domain only (value of "main_domain_only" API call argument)
    main_domain_only                BOOLEAN NOT NULL,

    -- Visit count
    visits                          BIGINT  NOT NULL

);

CREATE UNIQUE INDEX similarweb_estimated_visits_domain_month_mdo
    ON similarweb_estimated_visits (similarweb_domains_id, month, main_domain_only);
