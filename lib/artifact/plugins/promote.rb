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

require 'plugin'

require_relative 'common'

module Artifact
  module Plugins
    # promote an artifact to a different environment
    class Promote < Common
      # @!macro [attach] plugin_argument
      #   @!attribute $1
      #     $2
      plugin_argument :target_environment_name, description: 'target environment name for promotion'

      # promote artifact
      def after_initialize
        super

        promote_artifact
      end

      # promote an artifact to a different environment
      def promote_artifact
        source_key = "#{ @environment_name }/#{ @artifact }/#{ @version }.gpg"
        target_key = "#{ @target_environment_name }/#{ @artifact }/#{ @version }.gpg"

        subsection "Promote artifact from s3://#{ @bucket.name }/#{ source_key } to s3://#{ @bucket.name }/#{ target_key }", color: :green, prefix: @output_prefix unless @silent
        object = @bucket.object(target_key)
        object.copy_from(copy_source: "#{ @bucket.name }/#{ source_key }")

        sign_source_key = source_key + '.sign'
        if @bucket.object(sign_source_key).exists?
          sign_target_key = target_key + '.sign'

          subsection "Promote artifact signature from s3://#{ @bucket.name }/#{ sign_source_key } to s3://#{ @bucket.name }/#{ sign_target_key }", color: :green, prefix: @output_prefix unless @silent
          object = @bucket.object(sign_target_key)
          object.copy_from(copy_source: "#{ @bucket.name }/#{ sign_source_key }")
        end
      end
    end
  end
end
