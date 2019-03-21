


CREATE TYPE media_sitemap_pages_change_frequency AS ENUM (
    'always',
    'hourly',
    'daily',
    'weekly',
    'monthly',
    'yearly',
    'never'
);


-- Pages derived from XML sitemaps (stories or not)
CREATE TABLE media_sitemap_pages (
    media_sitemap_pages_id  BIGSERIAL   PRIMARY KEY,
    media_id                INT         NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,

    -- <loc> -- URL of the page
    url                     TEXT                                  NOT NULL,

    -- <lastmod> -- date of last modification of the URL
    last_modified           TIMESTAMP WITH TIME ZONE              NULL,

    -- <changefreq> -- how frequently the page is likely to change
    change_frequency        media_sitemap_pages_change_frequency  NULL,

    -- <priority> -- priority of this URL relative to other URLs on your site
    priority                DECIMAL(2, 1)                         NOT NULL DEFAULT 0.5,

    -- <news:title> -- title of the news article
    news_title              TEXT                                  NULL,

    -- <news:publication_date> -- article publication date
    news_publish_date       TIMESTAMP WITH TIME ZONE              NULL,

    CONSTRAINT media_sitemap_pages_priority_within_bounds
        CHECK (priority IS NULL OR (priority >= 0.0 AND priority <= 1.0))

);

CREATE UNIQUE INDEX media_sitemap_pages_url
    ON media_sitemap_pages (url);


