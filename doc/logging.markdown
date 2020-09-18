# Logging

## Python

Logging facilities are located in [`mediawords.util.log`](https://github.com/mediacloud/backend/blob/master/mediacloud/mediawords/util/log.py). Import the `create_logger()` factory:

```python
from mediawords.util.log import create_logger

log = create_logger(__name__)
```

...and then use various logger's helpers to log messages at various logging levels:

```python
log.info("This is an informational message")
log.debug("This is a debugging print")
# ...
```

Default logging level is `INFO`. You can set a different logging level by setting `MC_LOGGING_LEVEL` environment variable:

```bash
MC_LOGGING_LEVEL=DEBUG python3 script.py
```

## Perl

We are using [`Log::Log4perl`](https://mschilli.github.io/log4perl/) (Log4perl) for all logging. The basic idea of Log4perl is to send every log message with a category and priority and to associate those categories / priorities to appenders in a configuration file.

The Log4perl configuration file is in `log4perl.conf`, and the default just logs all messages of `WARN` or above to STDERR.

The following Log4perl calls are defined in and exported from `MediaWords::CommonLibs`:

* `FATAL()`
* `ERROR()`
* `WARN()`
* `INFO()`
* `DEBUG()`
* `TRACE()`
* `LOGDIE()`
* `LOGWARN()`
* `LOGCARP()`
* `LOGCLUCK()`
* `LOGCONFESS()`
* `LOGCROAK()`

To log, just invoked the function for the appropriate logging level, for example:

```perl
unless ( $story_content )
{
    DEBUG "SKIP - NO CONTENT";
}
```

If called from `MediaWords::TM::Mine`, this will get printed by the default STDERR appender as:

```
2016/04/13 13:59:35 MediaWords.TM.Mine: SKIP - NO CONTENT
```

To see more info from specific categories, add lines like the following to the `log4perl.conf` file:

```
log4perl.logger.MediaWords.TM.Mine = DEBUG, STDERR
```

Keep in mind that Perl will evaluate any expression passed as argument to a logging call.  If you anticipate that a logging call might be slow and will be called often (e.g. `TRACE()` call that uses `Dumper()` to print a huge hashref), consider using `LOGGING_CALL( sub { ... } )` syntax:

```perl
TRACE( sub {
    "Huge hashref that won't usually get logged anyway: "
        . Dumper( $huge_hashref )
} )
```

Use the following guidelines when deciding which logging level to use:

* `TRACE()` - detailed trace as low as line by line level, very noisy and generally useful only if a specific bit of code is giving trouble
* `DEBUG()` - traces basic operation of the code, pretty noisy but generally useful for following the basic flow of the code
* `INFO()` - stuff I would want to know even if not actively following that part of the code
* `WARN()` - something is off, equivalent of a Perl's `warn()`, but not worth directly notifying us
* `ERROR()` - something is off, and we should be notified of it
* `FATAL()` / `LOGDIE()` - fatal error, program should die and we should be notified
