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

require 'aws-sdk-s3'

require 'plugin'
require 'output_helper'

module Artifact
  # artifact plugins
  module Plugins
    # common plugin
    class Common < Plugin
      # @!macro [attach] plugin_argument
      #   @!attribute $1
      #     $2
      plugin_argument :artifact, description: 'artifact name'
      plugin_argument :bucket_name, description: 's3 bucket name'
      plugin_argument :bucket_region, description: 's3 bucket region'
      plugin_argument :environment_name, description: 'environment name'
      plugin_argument :version, description: 'artifact version'

      plugin_argument :access_key_id, description: 'aws access key id', optional: true
      plugin_argument :secret_access_key, description: 'aws secret access key', optional: true
      plugin_argument :debug, description: 'show debug output', optional: true, default: false
      plugin_argument :dryrun, description: 'dry run', optional: true, default: false
      plugin_argument :force, description: 'force action', optional: true, default: false
      plugin_argument :silent, description: 'do not output progress', optional: true, default: false
      plugin_argument :output_prefix, description: 'output prefix', optional: true, default: '|'

      # @raise [Aws::Sigv4::Errors::MissingCredentialsError]
      def after_initialize
        initialize_bucket
      end

      # initialize bucket
      #
      # @raise [Aws::Sigv4::Errors::MissingCredentialsError]
      def initialize_bucket
        if @access_key_id and @secret_access_key
          Aws.config.update(
            credentials: Aws::Credentials.new(@access_key_id, @secret_access_key)
          )
        end

        s3 = Aws::S3::Resource.new(
          region: @bucket_region
        )
        @bucket = s3.bucket(@bucket_name)
      end
    end
  end
end
