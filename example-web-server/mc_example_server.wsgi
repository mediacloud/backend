import os
import sys

# add this directory to the python path, so all the import work
basedir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(basedir)
sys.path.append(basedir+"../../")

# tell wsgi what to use as the application
from mc_example_server import app as application