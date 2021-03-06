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

require 'find'
require 'zip'

require 'plugin'

require_relative 'common'

module Artifact
  module Plugins
    # push artifact to s3
    class Push < Common
      # @!macro [attach] plugin_argument
      #   @!attribute $1
      #     $2
      plugin_argument :file_name_pattern, description: 'filename pattern'
      plugin_argument :target_directory, description: 'target directory'
      plugin_argument :workspace, description: 'workspace directory'
      plugin_argument :gpg_id, description: 'gpg id for encrypting'
      plugin_argument :gpg_passphrase, description: 'gpg passphrase', validator: Proc.new {|x| not x.nil? and not x.empty?}

      plugin_argument :exclude, description: 'exclude files and directories', optional: true, default: nil
      plugin_argument :sign, description: 'sign pushed artifact', optional: true, default: false
      plugin_argument :signer, description: 'gpg id for signing', optional: true, default: nil

      # push artifact to s3
      def after_initialize
        super

        find_artifact
        archive_artifact
        encrypt_artifact
        push_artifact
      end

      # find files for artifact
      def find_artifact
        Dir.chdir "#{@workspace}/#{@target_directory}"
        @artifacts = Find.find('./').find_all do |filename|
          filename =~ /#{@file_name_pattern}/ and
          not (@exclude and @exclude.find{|exclude| filename =~ /#{exclude}/})
        end
        v 'Found following artifacts: ' + @artifacts.inspect
      end

      # archive files for artifact
      def archive_artifact
        subsection 'Archive artifact', color: :green, prefix: @output_prefix unless @silent
        @data = Zip::OutputStream.write_buffer do |out|
          if @artifacts.length == 1
            file = @artifacts.shift
            v '+ ' + File.basename(file)
            out.put_next_entry(File.basename(file))
            out.write File.read(file)
          else
            @artifacts.each do |artifact|
              next if artifact == './'

              v '+ ' + artifact
              out.put_next_entry(artifact)
              if File.directory? artifact
                artifact += '/' unless artifact.end_with? '/'
                Zip::Entry.new(nil, artifact).write_to_zip_output_stream(out)
              elsif File.symlink? artifact
                unless (f=File.realpath(artifact)).start_with? File.realpath('./') and File.exist?(f)
                  v 'warning: doesn\'t add ' + artifact + ', because it points outside of target directory.'
                  next
                end

                d 's ' + artifact

                entry = Zip::Entry.new(nil, artifact)
                entry.gather_fileinfo_from_srcpath(artifact)
                entry.write_to_zip_output_stream(out)
              else
                d 'w ' + artifact
                out.write File.read(artifact)
              end
            end
          end
        end
        @data.rewind
        d "Zip::OutputStream length: #{@data.length}"

        raise 'ZIP data is empty' if @data.length == 0
      end

      # encrypt artifact
      def encrypt_artifact
        subsection 'Encrypt artifact', color: :green, prefix: @output_prefix unless @silent

        crypto = GPGME::Crypto.new recipients: @gpg_id
        @data = crypto.encrypt(@data, always_trust: true)

        d "GPGME::Crypto length: #{@data.to_s.length}"
        raise 'GPG data is empty' if @data.to_s.length == 0

        if @sign
          subsection 'Sign artifact', color: :green, prefix: @output_prefix unless @silent
          @sign_data = crypto.sign(@data, mode: GPGME::SIG_MODE_DETACH, signer: @signer, pinentry_mode: GPGME::PINENTRY_MODE_LOOPBACK, password: @gpg_passphrase)
          @data.seek 0
        end
        d "GPGME::Crypto length: #{@data.to_s.length}"

        raise 'GPG data is empty' if @data.to_s.length == 0
      rescue
        raise
      end

      # push artifact to s3
      def push_artifact
        key = "#{ @environment_name }/#{ @artifact }/#{ @version }.gpg"
        if @bucket.object(key).exists? and @environment_name != 'staging'
          subsection "Artifact s3://#{ @bucket.name }/#{ key } already exists. Aborting.", color: :green, prefix: @output_prefix unless @silent
        else
          subsection "Push artifact to s3://#{ @bucket.name }/#{ key }", color: :green, prefix: @output_prefix unless @silent
          object = @bucket.object(key)
          object.put(body: @data.read)

          if @sign
            signature_key = "#{ key }.sig"
            subsection "Push signature to s3://#{ @bucket.name }/#{ signature_key }", color: :green, prefix: @output_prefix unless @silent
            object = @bucket.object(signature_key)
            object.put(body: @sign_data.read)
          end
        end
      end
    end
  end
end
