#! /usr/bin/env python

from setuptools import setup
import sys, re, logging

version = ''
with open('mediacloud/__init__.py', 'r') as fd:
    version = re.search(r'^__version__\s*=\s*[\'"]([^\'"]*)[\'"]', fd.read(), re.MULTILINE).group(1)

if sys.argv[1]=="sdist":
    try:
        import pypandoc
        long_description = pypandoc.convert('README.md', 'rst')
    except(IOError, ImportError) as e:
        long_description = open('README.md').read()
        logging.exception(e)
    f = open('README.rst', 'w')
    f.write(long_description)
    f.close()

readme_rst = ''
with open('README.rst', 'r') as f:
    readme_rst = f.read()

setup(name='mediacloud',
    version=version,
    description='MediaCloud API Client Library',
    long_description=readme_rst,
    author='Rahul Bhargava',
    author_email='rahulb@media.mit.edu',
    url='http://mediacloud.org',
    packages={'mediacloud'},
    package_data={'':['LICENSE']},
    install_requires=['requests'],
    license='MIT',
    zip_safe=False,
    extras_require={'db': ['pymongo']}
)
