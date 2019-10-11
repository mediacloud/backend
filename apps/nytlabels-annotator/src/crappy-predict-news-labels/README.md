# Crappy `predict-news-labels`

Like Rahul's [NYTLabels annotator](https://github.com/mitmedialab/MediaCloud-NYT-News-Labeler), just crappier.


## Install

```bash
apt-get -y install brotli curl python3 python3-dev python3-setuptools
pip3 install -r requirements.txt
python3 -m nltk.downloader -d /usr/local/share/nltk_data punkt
./download_models.py
```


## Run

```bash
./nytlabels_http_server.py 8080
```

Requires ~8 GB of RAM.
