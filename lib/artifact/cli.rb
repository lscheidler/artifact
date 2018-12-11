# Copyright 2018 Lars Eric Scheidler
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'bundler/setup'

require 'optparse'

require 'overlay_config'
require 'plugin_manager'

require_relative 'plugins'

# get/promote/push artifacts in aws s3
module Artifact
  # command line interface
  class CLI
    def initialize
      set_defaults
      parse_arguments

      case @action
      when :get
        @pm['Artifact::Plugins::Get'].new @config
      when :promote
        @pm['Artifact::Plugins::Promote'].new @config
      when :push
        @pm['Artifact::Plugins::Push'].new @config
      else
        puts "Action #{@action} unknown."
      end
    rescue => exc
      puts exc.class.to_s + ': ' + exc.message
      puts '  ' + exc.backtrace.join("\n  ") if @config[:stacktrace]
      exit 1
    end

    # set defaults
    def set_defaults
      @script_name = File.basename($0)
      @config = OverlayConfig::Config.new config_scope: 'artifact', defaults: {
        bucket_name: 'my-bucket',
        bucket_region: 'eu-central-1',
        destination_directory: '/data/app/data',
        environment_name: 'staging',
        file_cache: false,
        gpg_id: '01234567890ABCDEF00000000000000000000000',
        output_prefix: "[#{@script_name}]",
        signer: '01234567890ABCDEF00000000000000000000000',
        target_environment_name: 'production'
      }
      @pm = PluginManager.instance
    end

    # parse command line arguments
    def parse_arguments
      @options = OptionParser.new do |opts|
        opts.banner = "Usage: #{@script_name} <action> [options]"

        opts.separator "\nactions:"
        opts.on('-g', '--get', 'get artifact from s3') do
          @action = :get
        end

        opts.on('-P', '--promote', 'promote artifact from staging to production') do
          @action = :promote
        end

        opts.on('-p', '--push', 'push artifact to s3') do
          @action = :push
        end

        opts.separator "\ngeneral options:"
        opts.on('--debug', 'show debug output') do
          @config[:debug] = true
        end

        opts.on('-f', '--force', 'force action') do
          @config[:force] = true
        end

        opts.on('-n', '--dryrun', 'dry run') do
          @config[:dryrun] = true
        end

        opts.on('-s', '--silent', 'do not output anything') do
          @config[:silent] = true
        end

        opts.on('--stacktrace', 'show stacktrace, if error occurs') do
          @config[:stacktrace] = true
        end

        opts.on('--verbose', 'verbose output') do
          @config[:verbose] = true
        end

        opts.separator "\ncommon options:"
        opts.on('-a', '--artifact STRING', 'set artifact name') do |artifact|
          @config[:artifact] = artifact
        end

        opts.on('-e', '--environment NAME', 'environment where to upload artifact', 'default: ' + @config[:environment_name]) do |environment_name|
          @config[:environment_name] = environment_name
        end

        opts.on('-v', '--version STRING', 'set artifact version to deploy') do |version|
          @config[:version] = version
        end

        ## GET
        opts.separator "\nget options:"
        opts.on('--compat-mode', 'use gpg binary directly to decrypt artifact') do
          @config[:compat_mode] = true
        end

        opts.on('--file-cache', 'use file cache to reduce memory usage', 'fork must be supported by OS') do
          @config[:file_cache] = true
        end

        opts.on('-d', '--destination DIRECTORY', 'set destination directory', "default: #{@config[:destination_directory]}") do |directory|
          @config[:destination_directory] = directory
        end

        opts.on('--verify', 'verify signature of artifact') do
          @config[:verify] = true
        end

        ## PROMOTE
        opts.separator "\npromote options:"
        opts.on('--source-version STRING', 'set source version') do |version|
          @config[:source_version] = version
        end

        opts.on('--target-environment NAME', 'set target environment name', 'default: ' + @config[:target_environment_name]) do |name|
          @config[:target_environment_name] = name
        end

        ## PUSH
        opts.separator "\npush options:"
        opts.on('--exclude PATTERN', 'set pattern to exclude files from artifact') do |pattern|
          @config[:exclude] ||= []
          @config[:exclude] << pattern
        end

        opts.on('-F', '--file-name-pattern PATTERN', 'set file name pattern') do |pattern|
          @config[:file_name_pattern] = pattern
        end

        opts.on('--sign', 'sign artifact with gpg key') do
          @config[:sign] = true
        end

        opts.on('--signer ID', Array, 'signer, which is used to sign artifact') do |signers|
          @config[:signer] = signers
        end

        opts.on('-t', '--target DIRECTORY', 'set target directory') do |directory|
          @config[:target_directory] = directory
        end

        opts.on('-w', '--workspace DIRECTORY', 'set workspace directory') do |directory|
          @config[:workspace] = directory
        end

        ## EXAMPLES
        opts.separator "
examples:
    # get artifact staging/tools/mailconsumer@1.0.1
    #{@script_name} --get --artifact tools/mailconsumer -v 1.0.1

    # promote artifact from staging/tools/mailconsumer@1.0.1 to production/tools/mailconsumer@1.0.1
    #{@script_name} -P -e staging -a tools/mailconsumer -v 1.0.1

    # promote artifact from staging/tools/mailconsumer@1.0.1-staging to production/tools/mailconsumer@1.0.1
    #{@script_name} -P -e staging -a tools/mailconsumer --source-version 1.0.1-staging -v 1.0.1

    # push artifact to staging/tools/mailconsumer@1.0.1
    #{@script_name} -p -e staging -a tools/mailconsumer -v 1.0.1 -t releases -w ~/tmp/data/tools/mailconsumer -F '.*mailconsumer.*.jar'
"
      end
      @options.parse!
    end
  end
end
