# mecab-ipadic-neologd

## Updating from upstream

`mecab-ipadic-neologd` authors seem to be fans of overwriting their commits with `git push --force`, so we maintain our own fork of the repository to be able to check out the same commit repeatedly as a submodule.

To update our `mecab-ipadic-neologd` fork from the upstream:

    # Go to submodule's directory
    cd lib/MediaWords/Languages/resources/ja/mecab-ipadic-neologd-dist/

    # Add upstream as a remote (if not added yet)
    git remote add upstream https://github.com/neologd/mecab-ipadic-neologd.git

    # Switch to submodule's "master" branch
    git checkout master
    
    # Fetch upstream
    git fetch upstream

    # Merge new changes from upstream into submodule
    git merge upstream/master

    # Push new changes to own fork's repository
    git push

Afterwards:

* Commit the parent (Media Cloud core) project with new commit hash for the submodule.
* Rerun `./install/install_mecab-ipadic-neologd.sh` to rebuild MeCab's dictionary.
