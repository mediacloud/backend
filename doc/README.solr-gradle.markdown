# Solr via Gradle

Media Cloud uses [Gradle](http://gradle.org/) to install, update and run [Apache Solr](https://lucene.apache.org/solr/).

## Installing Gradle

To install an up-to-date version of Gradle on Ubuntu:

1. Add Gradle's PPA repository (because the version of Gradle provided with Ubuntu is too old at the time of writing):

        sudo add-apt-repository -y ppa:cwchien/gradle
        sudo apt-get update

2. Install Gradle as any other system package:

        sudo apt-get install gradle

## Running Solr

To run Solr, execute:

    cd solr-gradle/
    gradle runSolr

Gradle will download (if it hasn't already) and install Solr and its dependencies under `solr-gradle/solr-dist/` directory, then run Solr as a Jetty application.

After starting Solr, access it as usual: <http://127.0.0.1:8983/solr>.

## Upgrading Solr

To upgrade Solr to a newer version:

1. Update `solrVersion` and `luceneMatchVersion` variables in `build.gradle`.
    * `solrVersion` is a Solr version you want to upgrade to, e.g. `4.6.0` or `4.10.3`. Gradle will download and install Solr from Maven Central Repository, so you can look up the exact version number in the [Solr's package version listing](http://search.maven.org/#search%7Cgav%7C1%7Cg%3A%22org.apache.solr%22%20AND%20a%3A%22solr%22).
    * `luceneMatchVersion` is a *version of Lucene various components of Solr
       adhere to* (as the example `solrconfig.xml` puts it), e.g. `LUCENE_46` or `4.10.3`. In newest versions of Solr, it matches the Solr's version.
2. Execute:

        gradle clean
        gradle runSolr

Gradle will download and install a newer version of Solr and its dependencies, then run Solr.

## Creating a new core ("collection")

To create a new Solr core (collection), e.g. `collection3`:

1. Initialize the configuration for the new core, e.g. by copying the configuration from another core and then modifying to your own needs:

        cd solr-gradle/
        cp -R mediacloud/collection1/ mediacloud/collection3/

2. In `build.gradle`, add a new property which points to the new core's data directory:

        System.setProperty("mediacloud.collection3.data.dir", "${solrDataDir}/collection3/")

3. In new core's `solrconfig.xml`, set the value of `<dataDir>` element to use the newly added property:

        <dataDir>${mediacloud.collection3.data.dir:}</dataDir>

4. Run Solr as usual. New core's data will be stored under the directory that you've just set (e.g. `/data/solr/collection3/`).
