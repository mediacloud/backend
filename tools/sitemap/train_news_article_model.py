#!/usr/bin/env python3

import argparse
import os
from typing import Optional

from keras import Sequential
from keras.layers import Dense
from numpy import loadtxt

from mediawords.util.log import create_logger

log = create_logger(__name__)


def train_news_article_model(training_sitemap_urls_file: str,
                             evaluation_sitemap_urls_file: Optional[str] = None,
                             model_output_dir: Optional[str] = None) -> None:
    """
    Train a news article detection model, optionally evaluate it, and optionally save the model to a directory.

    :param training_sitemap_urls_file: Path to file with sitemap-derived URLs and their vectors to use for training
        (see vectorize_sitemap_urls.py)
    :param evaluation_sitemap_urls_file: Path to file with sitemap-derived URLs and their vectors to use for evaluation;
        if None, trained model won't be evaluated.
    :param model_output_dir: Directory to which the trained model should be saved; if None, trained model won't be
        saved.
    """

    epoch_count = 2  # FIXME how many epochs do we really want?

    column_count = 17
    columns_to_read = [x + 1 for x in range(column_count)]

    log.info(f"Loading training data from '{training_sitemap_urls_file}'...")
    training_dataset = loadtxt(training_sitemap_urls_file, dtype=int, usecols=columns_to_read)
    training_input_data = training_dataset[:, :-1]  # Skip URL and desired output
    training_output_data = training_dataset[:, -1]  # Read only desired output

    log.info("Creating model...")
    model = Sequential()
    model.add(Dense(round(column_count * 1.5), input_dim=column_count - 1, activation='relu'))
    model.add(Dense(column_count - 1, activation='relu'))
    model.add(Dense(1, activation='sigmoid'))

    log.info("Compiling model...")
    model.compile(loss='binary_crossentropy', optimizer='adam', metrics=['accuracy'])

    log.info("Fitting model...")
    model.fit(training_input_data, training_output_data, epochs=epoch_count, batch_size=10)

    if evaluation_sitemap_urls_file:
        log.info(f"Loading evaluation data from {evaluation_sitemap_urls_file}...")
        evaluation_dataset = loadtxt(evaluation_sitemap_urls_file, dtype=int, usecols=columns_to_read)
        evaluation_input_data = evaluation_dataset[:, :-1]  # Skip URL and desired output
        evaluation_output_data = evaluation_dataset[:, -1]  # Read only desired output

        log.info("Evaluating model...")
        _, accuracy = model.evaluate(evaluation_input_data, evaluation_output_data)
        log.info('Accuracy: %.2f' % (accuracy * 100))

    if model_output_dir:
        log.info(f"Saving model to '{model_output_dir}'...")
        if not os.path.isdir(model_output_dir):
            os.mkdir(model_output_dir)

        model_structure_path = os.path.join(model_output_dir, 'model.json')
        model_weights_path = os.path.join(model_output_dir, 'model.h5')

        if os.path.isfile(model_structure_path):
            os.unlink(model_structure_path)
        if os.path.isfile(model_weights_path):
            os.unlink(model_weights_path)

        model_json = model.to_json()
        with open(model_structure_path, "w") as json_file:
            json_file.write(model_json)

        model.save_weights(model_weights_path)

    log.info("Done.")


def main():
    parser = argparse.ArgumentParser(description="Train news article detection model.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument("-t", "--training_path", type=str, required=True, help="Training sitemap URLs file path.")
    parser.add_argument("-e", "--evaluation_path", type=str, required=False, help="Evaluation sitemap URLs file path.")
    parser.add_argument("-o", "--model_output_dir", type=str, required=False, help="Directory to write the model to.")

    args = parser.parse_args()

    train_news_article_model(
        training_sitemap_urls_file=args.training_path,
        evaluation_sitemap_urls_file=args.evaluation_path,
        model_output_dir=args.model_output_dir,
    )


if __name__ == '__main__':
    main()
