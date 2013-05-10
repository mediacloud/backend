import os, sys
from flask import Flask, render_template
import json

parentdir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,parentdir) 
import mediacloud
from mediacloud.examples import ExampleMongoStoryDatabase

app = Flask(__name__)

db = ExampleMongoStoryDatabase('mediacloud')

@app.route("/")
def index():
    story_count_by_source = db.storyCountBySource()
    story_count = db.storyCount()
    return render_template("base.html",
        story_count = story_count,
        english_story_pct = int(round(100*db.englishStoryCount()/story_count)),
        story_counts_by_source = story_count_by_source,
        source_domains_json = json.dumps(story_count_by_source.keys()),
        max_story_id = db.getMaxStoryId()
    )

@app.route("/all_domains/info")
def all_domain_info():
    return render_template("data.js",
        story_length_info = _story_length_info(),
        reading_level_info = _reading_level_info()
    )

@app.route("/<domain>/info")
def domain_info(domain):
    return render_template("data_for_domain.js",
        domain_name = domain,
        story_count = db.storyCountForSource(domain),
        story_length_info = _story_length_info(domain),
        reading_level_info = _reading_level_info(domain)
    )

def _reading_level_info(domain=None, items_to_show=20):
    data = db.storyReadingLevelFreq(domain)
    return _assemble_info(data,1,items_to_show)

def _story_length_info(domain=None, bucket_size=200,items_to_show=20):
    data = db.storyLengthFreq(bucket_size, domain)
    return _assemble_info(data,bucket_size,items_to_show)

def _assemble_info(data,bucket_size,items_to_show):
    values = []
    for key in sorted(data.iterkeys()):
        values.append(data[key])
    values = values[:items_to_show]
    return {'values': values,
            'values_json': json.dumps(values),
            'final_bucket': bucket_size*items_to_show,
            'items_to_show': items_to_show,
            'biggest_value': max(values)
    }

if __name__ == "__main__":
    app.debug = True
    app.run()
