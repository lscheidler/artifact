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

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "artifact"

require 'fileutils'
require 'tmpdir'

Aws.config[:s3] = {
  stub_responses: {
    list_buckets: { buckets: [{name: 'my-bucket' }] }
  }
}

def initialize_test_data
  @bucket_name = 'my-bucket'
  @bucket_region = 'eu-central-1'

  @config = OverlayConfig::Config.new config_scope: 'artifact'
  @test_config = {
    bucket_name: @bucket_name,
    bucket_region: @bucket_region,
    gpg_id: '6986687D4705039AB6D27D6D39BC682A5434DA00',
    gpg_passphrase: 'notavalidpassphase',
    signer: '6986687D4705039AB6D27D6D39BC682A5434DA00',
    output_prefix: "[#{@script_name}]",
    target_environment_name: 'production',

    artifact: 'test',
    environment_name: 'staging',
    version: '0.1.0',
    silent: true,

    # Push
    target_directory: 'target',
    workspace: 'spec/data',

    # Get
    destination_directory: get_temporary_directory('release')
  }

  @config.insert(0, 'test', @test_config)

  @pwd = Dir.pwd
  @test_file_stat = File.stat('spec/data/target/test.txt')

  initialize_gpg
end

def initialize_gpg
  ENV.delete('GPG_AGENT_INFO')
  @gpg_home_dir = get_temporary_directory('gpg')
  GPGME::Engine.home_dir = @gpg_home_dir
  @gpg_public_key = 'spec/files/testkey_pub.gpg'
  @gpg_private_key = 'spec/files/testkey_sec.gpg'
end

def get_temporary_directory key
  directory = nil
  Tempfile.open(['artifact-','-' + key]) do |file|
    directory = file.path
    file.close!
  end
  Dir.mkdir directory
  FileUtils.chmod 'g=-rx,o=-rx', directory
  directory
end

def import_gpg_key type: :public
  case type
  when :private
    GPGME::Key.import(File.open(@gpg_private_key))
  else
    GPGME::Key.import(File.open(@gpg_public_key))
  end
end

def remove_gpg_keys
  (GPGME::Key.find(:secret)+GPGME::Key.find(:public)).each do |key|
    key.delete!
  end
end

def cleanup
  FileUtils.rm_rf @gpg_home_dir
  FileUtils.rm_rf @test_config[:destination_directory]
end
