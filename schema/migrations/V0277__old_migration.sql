


ALTER TABLE similarweb_metrics
    DROP CONSTRAINT similarweb_metrics_domain_month_key;

CREATE UNIQUE INDEX similarweb_metrics_domain_month
    ON similarweb_metrics (domain, month);

ALTER TABLE similarweb_metrics
    ALTER COLUMN visits TYPE BIGINT USING visits::bigint;




