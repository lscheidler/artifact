0.1.8 (2019-01-22)
==================

- support symlinks, when they point to files in target directory
- fix problem with empty files in compat mode

0.1.7 (2018-12-11)
==================

- introduce file\_cache configuration, which uses a file cache for artifact files.
  with this option enabled artifact uses fork to reduce memory usage for --get.

0.1.6 (2018-11-21)
==================

- use IO classes for reading zip file

0.1.5 (2018-11-08)
==================

- fix deletion bug for legacy mode (gpg 2.0)

0.1.4 (2018-10-18)
==================

- added --source-version to promote

0.1.3 (2018-09-13)
==================

- added fallback to popen for gpg 2.0 for --get
- added verbose output
- added exclude functionality to --push

0.1.2 (2018-09-11)
==================

- support for directories

0.1.1 (2018-09-04)
==================

- fix problem with tests
- fix runtime dependencies
- use rubyzip ~> 1.2.1

0.1.0 (2018-05-09)
==================

- initial release
