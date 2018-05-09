# Artifact


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'artifact', '0.1.0', git: 'https://github.com/lscheidler/artifact'
```

And then execute:

    $ bundle --binstubs bin

## Usage

```
bin/artifact -h
```

### push artifact

```
# push artifact to staging/tools/mailconsumer@1.0.1
artifact -p -e staging -a tools/mailconsumer -v 1.0.1 -t releases -w ~/tmp/data/tools/mailconsumer -F '.*mailconsumer.*.jar'
```

### get artifact

```
# get artifact staging/tools/mailconsumer@1.0.1
artifact --get --application tools/mailconsumer -v 1.0.1
```

### promote artifact

```
# promote artifact from staging/tools/mailconsumer@1.0.1 to production/tools/mailconsumer@1.0.1
artifact -P -e staging -a tools/mailconsumer -v 1.0.1
```

## Configuration

Following configuration files are going to be read:

- $HOME/.config/artifact/config.json
- $HOME/.config/artifact/credentials.json
- /etc/artifact/config.json
- /etc/artifact/credentials.json

A configuration setting is taken from the first file, where the setting exist (from to down).

### Available configuration settings

| name                        |           | default                                     | description                                   |
|-----------------------------|-----------|---------------------------------------------|-----------------------------------------------|
| access\_key\_id             | common    | -                                           | aws access key id                             |
| bucket\_name                | common    | my-bucket                                   | s3 bucket name                                |
| bucket\_region              | common    | eu-central-1                                | s3 bucket region                              |
| debug                       | common    | false                                       | show debug output                             |
| destination\_directory      | get       | /data/app/data                              | destination directory for deployed artifacts  |
| dryrun                      | common    | false                                       | dry run                                       |
| force                       | common    | false                                       | force action                                  |
| gpg\_id                     | get, push | 01234567890ABCDEF00000000000000000000000    | gpg id used for encrypting/decrypting         |
| gpg\_passphrase             | get, push | -                                           | passphrase for gpg key                        |
| group                       | get       | app                                         | unix group for deployed artifact              |
| output\_prefix              | common    | \[artifact\]                                | output prefix                                 |
| owner                       | get       | app                                         | unix ownder for deployed artifact             |
| secret\_access\_key         | common    | -                                           | aws secret access key                         |
| sign                        | push      | false                                       | sign pushed artifact                          |
| signer                      | push      | 01234567890ABCDEF00000000000000000000000    | used gpg id for signing                       |
| silent                      | common    | false                                       | do not output progress                        |
| target\_environment\_name   | promote   | production                                  | target environment name for promotion         |
| verify                      | get       | false                                       | verify downloaded artifact                    |

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/lscheidler/artifact.

## License

The gem is available as open source under the terms of the [Apache 2.0 License](http://opensource.org/licenses/Apache-2.0).

