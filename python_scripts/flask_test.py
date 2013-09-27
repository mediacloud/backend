#!/usr/bin/python

from flask import Flask, jsonify
import solr_query_wordcount_timer

app = Flask(__name__)

@app.route('/word_count/<int:task_id>', methods = ['GET'])
def get_task(task_id):
    task = filter(lambda t: t['id'] == task_id, tasks)
    if len(task) == 0:
        abort(404)
    return jsonify( { 'task': task[0] } )


@app.route('/')
def index():
    return "Hello, World!"

if __name__ == '__main__':
    app.run(debug = True)
