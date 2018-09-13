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

require 'fileutils'
require 'gpgme'
require 'gpgme/version'
require 'tempfile'
require 'zip'

require 'plugin'

require_relative 'common'

module Artifact
  module Plugins
    # deploy artifact
    class Get < Common
      # @!macro [attach] plugin_argument
      #   @!attribute $1
      #     $2
      plugin_argument :destination_directory, description: 'destination directory for deployed artifacts'
      plugin_argument :gpg_id, description: 'gpg id for decryption'
      plugin_argument :gpg_passphrase, description: 'gpg passphrase', validator: Proc.new {|x| not x.nil? and not x.empty?}

      plugin_argument :group, description: 'unix group for deployed artifact', optional: true, default: 'app'
      plugin_argument :owner, description: 'unix ownder for deployed artifact', optional: true, default: 'app'
      plugin_argument :verify, description: 'verify downloaded artifact', optional: true, default: false

      # @raise Aws::S3::Errors::NoSuchKey
      # @raise GPGME::Error::DecryptFailed
      def after_initialize
        super

        @release_directory = "#{ @destination_directory }/#{ @artifact }/releases/#{ @version }"

        if not File.exist? @release_directory or Dir.glob("#{@release_directory}/*").empty? or @force
          get_artifact
          decrypt_artifact
          unarchive_artifact
          adjust_permissions
        else
          subsection 'Application artifact already deployed', color: :yellow, prefix: @output_prefix unless @silent
        end
      end

      # get artifact from s3
      def get_artifact
        key = "#{ @environment_name }/#{ @artifact }/#{ @version }.gpg"
        subsection "Get artifact from s3://#{ @bucket.name }/#{ key }", color: :green, prefix: @output_prefix unless @silent
        object = @bucket.object(key)
        @data = object.get.body.read

        if @verify
          signature_key = "#{ key }.sig"
          subsection "Get signature from s3://#{ @bucket.name }/#{ signature_key }", color: :green, prefix: @output_prefix unless @silent
          object = @bucket.object(signature_key)
          @sign_data = object.get.body.read
        end
      end

      # decrypt artifact with gpg
      def decrypt_artifact
        if GPGME::VERSION == '1.0.8'
          decrypt_artifact_compat
        else
          decrypt_artifact_new
        end
      end

      # decrypt artifact, when ruby gpgme version == 1.0.8 (aka 2.0.5) is installed
      # uses gpg commandline program directly
      def decrypt_artifact_compat
        require 'tempfile'

        tempfile = Tempfile.new(["#{ @artifact.gsub('/', '_') }-#{ @version }_", '.gpg'])
        File.open(tempfile.path, 'w') do |io|
          io.print @data
        end

        if @verify
          subsection 'Verify artifact', color: :green, prefix: @output_prefix unless @silent
          signfile = Tempfile.new(["#{ @artifact.gsub('/', '_') }-#{ @version }_", '.gpg.sig'])
          File.open(signfile.path, 'w') do |io|
            io.print @sign_data
          end
          p @data.class
          FileUtils.cp tempfile.path, '/var/tmp/tempfiles/test.gpg'
          FileUtils.cp signfile.path, '/var/tmp/tempfiles/test.gpg.sig'
          %x{echo "#{ @gpg_passphrase }" | gpg --batch --passphrase-fd 0 --verify #{signfile.path} #{ tempfile.path }}
          raise 'Verification failed' if not $?.success?
        end

        subsection 'Decrypt artifact', color: :green, prefix: @output_prefix unless @silent

        %x{echo "#{ @gpg_passphrase }" | gpg --batch --passphrase-fd 0 --decrypt-files #{ tempfile.path }}
        raise 'Decryption failed' if not $?.success?

        @data = File.open(tempfile.path.gsub(/\.gpg$/, ''))
      end

      # decrypt artifact with ruby gpgme version > 1.0.8
      def decrypt_artifact_new
        crypto = GPGME::Crypto.new pinentry_mode: GPGME::PINENTRY_MODE_LOOPBACK, password: @gpg_passphrase

        if @verify
          subsection 'Verify artifact', color: :green, prefix: @output_prefix unless @silent
          crypto.verify(@sign_data, :signed_text => @data) do |signature|
            raise GPGME::Error::BadSignature.new GPGME::GPG_ERR_BAD_SIGNATURE unless signature.valid?
          end
        end

        subsection 'Decrypt artifact', color: :green, prefix: @output_prefix unless @silent
        @data = crypto.decrypt(@data)
      rescue
        save_artifact '.gpg'
        raise
      end

      # unarchive artifact
      def unarchive_artifact
        subsection 'Unarchive artifact', color: :green, prefix: @output_prefix unless @silent
        FileUtils.mkdir_p @release_directory
        Zip::File.open_buffer(@data.read) do |zip_file|
          # Handle entries one by one
          zip_file.each do |entry|
            # Extract to file/directory/symlink
            v '+ ' + "#{@release_directory}/#{entry.name}"
            entry.extract("#{@release_directory}/#{entry.name}") do
              @force
            end
          end
        end
      rescue
        save_artifact '.zip'
        raise
      end

      # adjust file and directory permissions
      def adjust_permissions
        # adjust base directory permission
        subsection 'Adjust file and directory permissions', color: :green, prefix: @output_prefix unless @silent
        FileUtils.chown @owner, @group, "#{ @destination_directory }/#{ @artifact }"
        FileUtils.chmod "u+w,g+ws", "#{ @destination_directory }/#{ @artifact }"

        # adjust release directory permission
        FileUtils.chown_R @owner, @group, @release_directory
      end

      # save *@data* to a temporary path with *extension*, if *@debug* is true
      def save_artifact extension
        if @debug
          tempfile = Tempfile.new(["#{ @artifact.gsub('/', '_') }-#{ @version }_", extension])
          path = tempfile.path
          tempfile.close(true)

          subsection "Saving data to #{path}", color: :yellow, prefix: @output_prefix
          File.open(path, 'w') do |io|
            io.print @data
          end
        end
      end
    end
  end
end
