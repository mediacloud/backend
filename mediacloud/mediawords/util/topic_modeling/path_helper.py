"""Fix path to help imports."""

import sys
from os.path import dirname, abspath

sys.path.append(dirname(dirname(dirname(dirname(abspath(__file__))))))
