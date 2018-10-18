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

require "spec_helper"

describe Artifact do
  let(:stub_resource) { Aws::S3::Resource.new(stub_responses: true, region: @bucket_region) }

  before(:all) do
    initialize_test_data
    @pm = PluginManager.instance
  end

  after(:all) do
    cleanup
  end

  it "has a version number" do
    expect(Artifact::VERSION).not_to be nil
  end

  describe Artifact::Plugins::Push do
    before(:all) do
      import_gpg_key
      import_gpg_key type: :private

      class TestPush < @pm['Artifact::Plugins::Push']
        attr_accessor :artifacts, :data, :sign_data

        def after_initialize
          initialize_bucket
        end
      end
    end

    context 'finds one file' do
      before(:all) do
        @test_config[:file_name_pattern] = '.*\.txt'
        @test_config[:sign] = true
      end

      after() do
        Dir.chdir @pwd
      end

      it 'should find all txt files in spec/data/target' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        @push = TestPush.new @config
        @push.find_artifact

        expect(@push.artifacts.length).to be(1)
        expect(@push.artifacts).to include('./test.txt')
      end

      it 'should create a zip file' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        @push = TestPush.new @config
        @push.find_artifact
        @push.archive_artifact

        expect(@push.data).not_to be(nil)
        # TODO check content of zip
      end

      it 'should create a zip file' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        @push = TestPush.new @config
        @push.find_artifact
        @push.archive_artifact
        @push.encrypt_artifact

        expect(@push.data).not_to be(nil)
        expect(@push.data.class).to be(GPGME::Data)
      end

      it 'should push artifact to s3' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        objects = []
        stub_resource.client.stub_responses(:put_object, -> (context) {
          object = Aws::S3::Types::GetObjectOutput.new(
                     content_type: context.params[:content_type],
                     body: StringIO.new(context.params[:body])
                   )
          objects << object
          stub_resource.client.stub_responses(:get_object, objects)
        })
        stub_resource.client.stub_responses(:get_object, objects)

        @push = TestPush.new @config
        @push.find_artifact
        @push.archive_artifact
        @push.encrypt_artifact
        @push.push_artifact

        expect(stub_resource.client.get_object(bucket: @bucket_name, key: '').body.read).to eq(@push.data.to_s)
        expect(stub_resource.client.get_object(bucket: @bucket_name, key: '').body.read).to eq(@push.sign_data.to_s)
      end
    end

    context 'finds multiple files' do
      before(:all) do
        @test_config[:file_name_pattern] = '.*'
      end

      after() do
        Dir.chdir @pwd
      end

      it 'should find all files in spec/data/target' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        @push = TestPush.new @config
        @push.find_artifact

        expect(@push.artifacts.length).to be(3)
        expect(@push.artifacts).to eq(['./', './README', './test.txt'])
      end

      it 'should run without an error' do
        @push = TestPush.new @config
        @push.find_artifact
        @push.archive_artifact
        @push.encrypt_artifact
      end
    end

    context 'exclude specific files' do
      before(:all) do
        @test_config[:file_name_pattern] = '.*'
        @test_config[:exclude] = ['RE.*']
      end

      after() do
        @test_config[:exclude] = nil
        Dir.chdir @pwd
      end

      it 'should find all files in spec/data/target except README' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        @push = TestPush.new @config
        @push.find_artifact

        expect(@push.artifacts.length).to be(2)
        expect(@push.artifacts).to eq(['./', './test.txt'])
      end
    end

    context 'artifact already exists' do
      before(:all) do
        @test_config[:file_name_pattern] = '.*\.txt'
        @test_config[:sign] = true
      end

      after() do
        Dir.chdir @pwd
      end

      context 'staging' do
        it 'should push and override artifact to s3, if artifact already exists' do
          expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
          objects = [
          ]
          stub_resource.client.stub_responses(:put_object, -> (context) {
            object = Aws::S3::Types::GetObjectOutput.new(
                       content_type: context.params[:content_type],
                       body: StringIO.new(context.params[:body])
                     )
            objects << object
            stub_resource.client.stub_responses(:get_object, objects)
            stub_resource.client.stub_responses(:head_object, [
              Aws::S3::Types::GetObjectOutput.new(
                body: StringIO.new('key exist')
              )
            ])
          })
          stub_resource.client.stub_responses(:get_object, objects)

          @push = TestPush.new @config
          @push.find_artifact
          @push.archive_artifact
          @push.encrypt_artifact
          @push.push_artifact

          expect(stub_resource.client.get_object(bucket: @bucket_name, key: '').body.read).to eq(@push.data.to_s)
          expect(stub_resource.client.get_object(bucket: @bucket_name, key: '').body.read).to eq(@push.sign_data.to_s)
        end
      end

      context 'production' do
        before do
          @test_config[:environment_name] = 'production'
          @test_config[:silent] = false
        end
        after do
          @test_config[:environment_name] = 'staging'
          @test_config[:silent] = true
        end

        it 'should not push artifact to s3, if artifact already exists' do
          expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
          objects = [
          ]
          stub_resource.client.stub_responses(:put_object, -> (context) {
            object = Aws::S3::Types::GetObjectOutput.new(
                       content_type: context.params[:content_type],
                       body: StringIO.new(context.params[:body])
                     )
            objects << object
            stub_resource.client.stub_responses(:get_object, objects)
            stub_resource.client.stub_responses(:head_object, [
              Aws::S3::Types::GetObjectOutput.new(
                body: StringIO.new('key exist')
              )
            ])
          })
          stub_resource.client.stub_responses(:get_object, objects)

          expect {
            @push = TestPush.new @config
            @push.find_artifact
            @push.archive_artifact
            @push.encrypt_artifact
            @push.push_artifact
          }.to output(/Artifact s3:\/\/my-bucket\/production\/test\/0.1.0.gpg already exists. Aborting./).to_stdout

          expect(stub_resource.client.get_object(bucket: @bucket_name, key: '').body.read).to eq('')
        end
      end
    end

    context 'finds multiple files with subdirectories' do
      before(:all) do
        @test_config[:file_name_pattern] = '.*'
        @test_config[:target_directory] = 'target_with_subdirectories'
      end

      after() do
        Dir.chdir @pwd
      end

      it 'should find all files in spec/data/target' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        @push = TestPush.new @config
        @push.find_artifact

        expect(@push.artifacts.length).to be(6)
        expect(@push.artifacts).to eq(['./', './css', './css/app.css', './index.html', './js', './js/app.js'])
      end

      it 'should run without an error' do
        @push = TestPush.new @config
        @push.find_artifact
        @push.archive_artifact
        @push.encrypt_artifact
      end
    end
  end

  describe Artifact::Plugins::Get do
    before(:all) do
      class TestGet < @pm['Artifact::Plugins::Get']
        attr_accessor :data, :sign_data

        def after_initialize
          initialize_bucket
          @release_directory = "#{ @destination_directory }/#{ @artifact }/releases/#{ @version }"
        end
      end
    end

    before do
      stub_resource.client.stub_responses(:get_object, [
                                            Aws::S3::Types::GetObjectOutput.new(
                                              body: File.open('spec/data/0.1.0.gpg')
                                            ),
                                            Aws::S3::Types::GetObjectOutput.new(
                                              body: File.open('spec/data/0.1.0.gpg.sign')
                                            )
                                          ])
    end

    context 'without verification' do
      it 'should get artifact' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        @get = TestGet.new @config

        @get.get_artifact
        expect(@get.data).not_to be(nil)
        expect(@get.sign_data).to be(nil)
      end
    end

    context 'with verification' do
      before(:all) do
        @test_config[:verify] = true
      end

      after(:all) do
        @test_config[:verify] = false
      end

      it 'should get artifact' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        @get = TestGet.new @config

        @get.get_artifact
        expect(@get.data).not_to be(nil)
        expect(@get.sign_data).not_to be(nil)
      end

      it 'should decrypt artifact' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        @get = TestGet.new @config

        @get.get_artifact
        @get.decrypt_artifact
        expect(@get.data).not_to be(nil)
        expect(@get.sign_data).not_to be(nil)
      end

      it 'should unarchive artifact' do
        expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
        @get = TestGet.new @config

        @get.get_artifact
        @get.decrypt_artifact
        @get.unarchive_artifact

        expect(File.exist? @test_config[:destination_directory] + '/test/releases/0.1.0/test.txt').to be(true)
        expect(File.read @test_config[:destination_directory] + '/test/releases/0.1.0/test.txt').to eq(File.read('spec/data/target/test.txt'))
      end
    end
  end

  describe Artifact::Plugins::Promote do
    before(:all) do
      class TestPromote < @pm['Artifact::Plugins::Promote']
        attr_accessor :artifacts, :data, :sign_data

        def after_initialize
          initialize_bucket
          @source_version ||= @version
        end
      end
    end

    before do
      stub_resource.client.stub_responses(:get_object, [
                                            Aws::S3::Types::GetObjectOutput.new(
                                              body: StringIO.new('0.1.0.gpg')
                                            ),
                                            Aws::S3::Types::GetObjectOutput.new(
                                              body: StringIO.new('0.1.0.gpg.sign')
                                            )
                                          ])
    end

    it 'should promote artifact' do
      expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
      keys = []
      stub_resource.client.stub_responses(:copy_object, -> (context) {
        keys << context.params[:copy_source]
        keys << context.params[:key]
        context
      })
      @promote = TestPromote.new @config

      @promote.promote_artifact

      expect(keys).to eq(['my-bucket/staging/test/0.1.0.gpg', 'production/test/0.1.0.gpg', 'my-bucket/staging/test/0.1.0.gpg.sign', 'production/test/0.1.0.gpg.sign'])
    end

    it 'should promote artifact from different source version' do
      @config.source_version = "0.1.0-SNAPSHOT"

      expect(Aws::S3::Resource).to receive(:new).and_return(stub_resource)
      keys = []
      stub_resource.client.stub_responses(:copy_object, -> (context) {
        keys << context.params[:copy_source]
        keys << context.params[:key]
        context
      })
      @promote = TestPromote.new @config

      @promote.promote_artifact

      expect(keys).to eq(['my-bucket/staging/test/0.1.0-SNAPSHOT.gpg', 'production/test/0.1.0.gpg', 'my-bucket/staging/test/0.1.0-SNAPSHOT.gpg.sign', 'production/test/0.1.0.gpg.sign'])

      @config.source_version = nil
    end
  end
end
