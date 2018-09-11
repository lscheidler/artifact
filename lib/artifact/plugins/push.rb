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
        @artifacts = Find.find('./').find_all{|x| x =~ /#{@file_name_pattern}/}
      end

      # archive files for artifact
      def archive_artifact
        subsection 'Archive artifact', color: :green, prefix: @output_prefix unless @silent
        @data = Zip::OutputStream.write_buffer do |out|
          if @artifacts.length == 1
            file = @artifacts.shift
            out.put_next_entry(File.basename(file))
            out.write File.read(file)
          else
            @artifacts.each do |artifact|
              next if artifact == './'

              out.put_next_entry(artifact)
              if not File.directory? artifact
                out.write File.read(artifact)
              end
            end
          end
        end
        @data.rewind
      end

      # encrypt artifact
      def encrypt_artifact
        subsection 'Encrypt artifact', color: :green, prefix: @output_prefix unless @silent
        crypto = GPGME::Crypto.new pinentry_mode: GPGME::PINENTRY_MODE_LOOPBACK, password: @gpg_passphrase, recipients: @gpg_id
        @data = crypto.encrypt(@data, always_trust: true)

        if @sign
          subsection 'Sign artifact', color: :green, prefix: @output_prefix unless @silent
          @sign_data = crypto.sign(@data, pinentry_mode: GPGME::PINENTRY_MODE_LOOPBACK, mode: GPGME::SIG_MODE_DETACH, password: @gpg_passphrase, signer: @signer)
          @data.seek 0
        end
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
