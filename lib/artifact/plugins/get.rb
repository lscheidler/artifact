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
require 'stringio'
require 'tempfile'
require 'zip'

require 'plugin'

require_relative 'common'

# monkey patch to support symlinks again
module Zip
  class Entry
    @@base_dir = nil

    def self.base_dir= directory
      @@base_dir = directory
    end

    def create_symlink(dest_path)
      stat = nil
      begin
        stat = ::File.lstat(dest_path)
      rescue Errno::ENOENT
      end

      io     = get_input_stream
      linkto = io.read

      if stat
        if stat.symlink?
          if ::File.readlink(dest_path) == linkto
            return
          else
            raise ::Zip::DestinationFileExistsError,
                  "Cannot create symlink '#{dest_path}'. " \
                      'A symlink already exists with that name'
          end
        else
          raise ::Zip::DestinationFileExistsError,
                "Cannot create symlink '#{dest_path}'. " \
                    'A file already exists with that name'
        end
      end

      # sanity check
      # if symlink points outsite of zip, abort
      if linkto.start_with? '/' or (linkto.start_with? '../' and (not @@base_dir or not ::File.expand_path(::File.join(::File.dirname(dest_path), linkto)).start_with? @@base_dir))
        puts "WARNING: skipped symlink #{dest_path}"
        return
      end

      ::File.symlink(linkto, dest_path)
    end
  end
end

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

      plugin_argument :compat_mode, description: 'decrypt artifact with gpg binary', optional: true, default: false
      plugin_argument :file_cache, description: 'use file cache', optional: true, default: false
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
        @artifact_gpg = run(file_cache: (@file_cache or is_compat_mode?), extension: '.gpg') do
          subsection "Get artifact from s3://#{ @bucket.name }/#{ key }", color: :green, prefix: @output_prefix unless @silent
          object = @bucket.object(key)
          object.get.body
        end

        if @verify
          @artifact_sign = run(file_cache: (@file_cache or is_compat_mode?), extension: '.sign') do
            signature_key = "#{ key }.sig"
            subsection "Get signature from s3://#{ @bucket.name }/#{ signature_key }", color: :green, prefix: @output_prefix unless @silent
            object = @bucket.object(signature_key)
            object.get.body
          end
        end
      end

      # decrypt artifact with gpg
      def decrypt_artifact
        if is_compat_mode?
          decrypt_artifact_compat
        else
          decrypt_artifact_new
        end
      end

      # decrypt artifact, when ruby gpgme version == 1.0.8 (aka 2.0.5) is installed
      # uses gpg commandline program directly
      def decrypt_artifact_compat
        require 'tempfile'

        v 'gpg file stat: ' + File.stat(@artifact_gpg.path).inspect

        if @verify
          subsection 'Verify artifact', color: :green, prefix: @output_prefix unless @silent

          %x{echo "#{ @gpg_passphrase }" | gpg --batch --passphrase-fd 0 --verify #{@artifact_sign.path} #{ @artifact_gpg.path }}
          raise 'Verification failed' if not $?.success?
        end

        subsection 'Decrypt artifact', color: :green, prefix: @output_prefix unless @silent

        @artifact_zip = run(file_cache: true, extension: '.zip') do |file|
          #%x{echo "#{ @gpg_passphrase }" | gpg --batch --passphrase-fd 0 --output #{file.path} --decrypt #{ @artifact_gpg.path }}
          %x{echo "#{ @gpg_passphrase }" | gpg --batch --passphrase-fd 0 --decrypt-files #{ @artifact_gpg.path }}
          FileUtils.mv @artifact_gpg.path.gsub(/\.gpg/, ''), file.path
          raise 'Decryption failed' if not $?.success?
          ObjectSpace.undefine_finalizer(file) if @debug
          File.open(file.path)
        end
        v 'zip file stat: ' + File.stat(@artifact_zip.path).inspect
      end

      # decrypt artifact with ruby gpgme version > 1.0.8
      def decrypt_artifact_new
        crypto = GPGME::Crypto.new pinentry_mode: GPGME::PINENTRY_MODE_LOOPBACK, password: @gpg_passphrase

        if @verify
          subsection 'Verify artifact', color: :green, prefix: @output_prefix unless @silent
          crypto.verify(@artifact_sign.io, :signed_text => @artifact_gpg.io) do |signature|
            raise GPGME::Error::BadSignature.new GPGME::GPG_ERR_BAD_SIGNATURE unless signature.valid?
          end
          @artifact_gpg.io.rewind
        end

        subsection 'Decrypt artifact', color: :green, prefix: @output_prefix unless @silent
        @artifact_zip = run(extension: '.zip') do
          StringIO.new(crypto.decrypt(@artifact_gpg.io).read)
        end
      rescue
        save_artifact '.gpg'
        raise
      end

      # unarchive artifact
      def unarchive_artifact
        subsection 'Unarchive artifact', color: :green, prefix: @output_prefix unless @silent
        FileUtils.mkdir_p @release_directory
        run() do
          # monkey patch for base directory to prevent creation of symlinks pointing outsite of @release_directory
          Zip::Entry.base_dir = @release_directory

          Zip::File.open_buffer(@artifact_zip.io) do |zip_file|
            v 'zip entries: ' + zip_file.size.inspect

            # Handle entries one by one
            zip_file.each do |entry|
              # Extract to file/directory/symlink
              v '+ ' + "#{@release_directory}/#{entry.name}"
              entry.extract("#{@release_directory}/#{entry.name}") do
                @force
              end
            end
          end
          nil
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

      def run extension: '.data',file_cache: @file_cache,  &block
        Runner.new extension: extension, file_cache: file_cache, prefix: "#{ @artifact.gsub('/', '_') }-#{ @version }_", block: block
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

      def is_compat_mode?
        GPGME::VERSION == '1.0.8' or @compat_mode
      end

      class Runner
        attr_accessor :path, :io

        def initialize block:, file_cache:, prefix:, extension: '.data'
          if file_cache
            @io = Tempfile.new([prefix, extension])
            pid = fork do
              begin
                ObjectSpace.undefine_finalizer(@io)

                data = block.yield @io
                while not data.nil? and line=data.gets
                  @io.print line
                end
                @io.rewind
              rescue => e
                puts e.class.to_s + ' ' + e.message
                raise
              end
            end
            Process.wait(pid)

            raise 'failed' if not $?.success?

            @path = @io.path
          else
            @io = block.yield @io
          end
        end
      end
    end
  end
end
