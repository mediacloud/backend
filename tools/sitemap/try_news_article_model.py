#!/usr/bin/env python3

import argparse
import os

import numpy as np
from keras.engine.saving import model_from_json

from mediawords.util.log import create_logger
from mediawords.util.sitemap.url_vectors import URLFeatureExtractor

log = create_logger(__name__)


def try_news_article_model(model_dir: str) -> None:
    """
    Load the news article detection model and try it out against a couple of URLs.
    :param model_dir: Directory with the model
    """
    assert os.path.isdir(model_dir), f"Model directory does not exist at '{model_dir}'"

    model_structure_path = os.path.join(model_dir, 'model.json')
    model_weights_path = os.path.join(model_dir, 'model.h5')

    assert os.path.isfile(model_structure_path), f"Model structure file does not exist at '{model_structure_path}'"
    assert os.path.isfile(model_weights_path), f"Model weights file does not exist at '{model_weights_path}'"

    log.info(f"Loading model structure from '{model_structure_path}'...")
    with open(model_structure_path, "r") as model_structure_file:
        model_structure_json = model_structure_file.read()
        model = model_from_json(model_structure_json)

    log.info(f"Loading model weights from '{model_weights_path}'...")
    model.load_weights(model_weights_path)

    log.info("Compiling model...")
    model.compile(loss='binary_crossentropy', optimizer='adam', metrics=['accuracy'])

    log.info("Trying out model...")

    article_urls = [
        'https://www.nytimes.com/2019/08/08/climate/climate-change-food-supply.html',
        (
            'https://www.delfi.lt/news/daily/lithuania/sunu-i-ligonine-isgabenes-pogrebnojus-kaltina-simasiu-mano-'
            'vaikas-verkia-o-jie-politikuoja.d?id=81942177'
        ),
        (
            'https://www.15min.lt/naujiena/aktualu/lietuva/astravo-atomineje-elektrineje-ivykus-rimtai-avarijai-'
            'vilnieciu-nebutu-kur-evakuoti-56-1185646'
        ),
        (
            'https://globalvoices.org/2019/08/07/two-universities-sign-historic-agreement-on-slavery-reparations-in-'
            'the-caribbean/'
        ),
        'https://www.kdnuggets.com/2016/10/machine-learning-detect-malicious-urls.html',
        'https://www.facebook.com/zuck/posts/10108280403736331',
    ]

    not_article_urls = [
        'https://www.nytimes.com/',
        'https://www.nytimes.com/section/business',
        'https://www.nytimes.com/newsletters',
        'https://www.delfi.lt/',
        'https://www.delfi.lt/krepsinis/turnyrai/europos-taure/',
        'https://www.15min.lt/naujienos/aktualu/pasaulis',
        'https://globalvoices.org/',
        'https://globalvoices.org/-/world/western-europe/',
        'https://globalvoices.org/-/world/western-europe,eastern-central-europe/',
        'https://facebook.com/globalvoicesonline/',
        'https://en.support.wordpress.com/posts/categories/',
        'http://example.com/tag/news/',
        'https://disqus.com/by/hussainahmedtariq/',
        'https://www.facebook.com/zuck',
    ]

    for url in article_urls + not_article_urls:
        url_vectors = URLFeatureExtractor(url).vectors()

        x = np.array([url_vectors])

        prediction = model.predict(x)[0][0]
        print(f"* {prediction:.2f} == {url}")


def main():
    parser = argparse.ArgumentParser(description="Try out a news article detection model.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-m", "--model_dir", type=str, required=True,
                        help="Directory with model structure and weights.")

    args = parser.parse_args()

    try_news_article_model(model_dir=args.model_dir)


if __name__ == '__main__':
    main()
