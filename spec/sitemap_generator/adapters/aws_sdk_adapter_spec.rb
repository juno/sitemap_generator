require 'spec_helper'
require 'aws-sdk-core'
require 'aws-sdk-s3'

RSpec.describe SitemapGenerator::AwsSdkAdapter do
  subject(:adapter)  { described_class.new('bucket', **options) }

  let(:location) { SitemapGenerator::SitemapLocation.new(compress: compress) }
  let(:options) { {} }
  let(:compress) { nil }

  shared_examples 'it writes the raw data to a file and then uploads that file to S3 via S3 Resource' do |acl, cache_control, content_type|
    before do
      allow(adapter).to receive(:s3_transfer_manager_available?).and_return(false)
    end

    it 'writes the raw data to a file and then uploads that file to S3' do
      s3_object = double(:s3_object)
      s3_resource = double(:s3_resource)
      s3_bucket_resource = double(:s3_bucket_resource)
      expect(adapter).to receive(:s3_resource).and_return(s3_resource)
      expect(s3_resource).to receive(:bucket).with('bucket').and_return(s3_bucket_resource)
      expect(s3_bucket_resource).to receive(:object).with('path_in_public').and_return(s3_object)
      expect(location).to receive(:path_in_public).and_return('path_in_public')
      expect(location).to receive(:path).and_return('path')
      expect(s3_object).to receive(:upload_file).with('path', hash_including(
        acl: acl,
        cache_control: cache_control,
        content_type: content_type
      )).and_return(nil)
      expect_any_instance_of(SitemapGenerator::FileAdapter).to receive(:write).with(location, 'raw_data')
      adapter.write(location, 'raw_data')
    end
  end

  shared_examples 'it writes the raw data to a file and then uploads that file to S3 via TransferManager' do |acl, cache_control, content_type|
    before do
      allow(adapter).to receive(:s3_transfer_manager_available?).and_return(true)
    end

    it 'writes the raw data to a file and then uploads that file to S3' do
      s3_client = double(:s3_client)
      s3_transfer_manager = double(:s3_transfer_manager)

      expect(Aws::S3::Client).to receive(:new).with({}).and_return(s3_client)
      expect(Aws::S3::TransferManager).to receive(:new).with(client: s3_client).and_return(s3_transfer_manager)
      expect(location).to receive(:path).and_return('path')
      expect(location).to receive(:path_in_public).and_return('path_in_public')
      expect(s3_transfer_manager).to receive(:upload_file).with('path', hash_including(
        acl: acl,
        bucket: 'bucket',
        cache_control: cache_control,
        content_type: content_type,
        key: 'path_in_public'
      )).and_return(nil)
      expect_any_instance_of(SitemapGenerator::FileAdapter).to receive(:write).with(location, 'raw_data')

      adapter.write(location, 'raw_data')
    end
  end

  shared_examples "deprecated option" do |deprecated_key, new_key|
    context 'when a deprecated option set' do
      context 'when it is not nil' do
        let(:options) do
          { deprecated_key => 'value' }
        end

        it 'sets the option' do
          expect(adapterOptions[new_key]).to eq('value')
        end

        context 'when the new option key is set' do
          context 'when it is not nil' do
            let(:options) do
              { deprecated_key => 'value', new_key => 'new_endpoint' }
            end

            it 'does not override it' do
              expect(adapterOptions[new_key]).to eq('new_endpoint')
            end
          end

          context 'when it is nil' do
            let(:options) do
              { deprecated_key => 'value', new_key => nil }
            end

            it 'overrides it' do
              expect(adapterOptions[new_key]).to eq('value')
            end
          end
        end
      end

      context 'when it is nil' do
        let(:options) do
          { deprecated_key => nil }
        end

        it 'does not set the option' do
          expect(adapterOptions).not_to have_key(new_key)
        end
      end
    end
  end

  context 'when Aws::S3::Resource is not defined' do
    it 'raises a LoadError' do
      hide_const('Aws::S3::Resource')
      expect do
        load File.expand_path('./lib/sitemap_generator/adapters/aws_sdk_adapter.rb')
      end.to raise_error(LoadError, /Error: `Aws::S3::Resource` and\/or `Aws::Credentials` are not defined/)
    end
  end

  context 'when Aws::Credentials is not defined' do
    it 'raises a LoadError' do
      hide_const('Aws::Credentials')
      expect do
        load File.expand_path('./lib/sitemap_generator/adapters/aws_sdk_adapter.rb')
      end.to raise_error(LoadError, /Error: `Aws::S3::Resource` and\/or `Aws::Credentials` are not defined/)
    end
  end

  describe '#write' do
    context 'when TransferManager is unavailable' do
      context 'with no compress option' do
        it_behaves_like 'it writes the raw data to a file and then uploads that file to S3 via S3 Resource', 'public-read', 'private, max-age=0, no-cache', 'application/xml'
      end

      context 'with compress true' do
        let(:compress) { true }

        it_behaves_like 'it writes the raw data to a file and then uploads that file to S3 via S3 Resource', 'public-read', 'private, max-age=0, no-cache', 'application/x-gzip'
      end

      context 'with acl and cache control configured' do
        let(:options) do
          { acl: 'private', cache_control: 'public, max-age=3600' }
        end

        it_behaves_like 'it writes the raw data to a file and then uploads that file to S3 via S3 Resource', 'private', 'public, max-age=3600', 'application/xml'
      end
    end

    context 'when TransferManager is available' do
      context 'with no compress option' do
        it_behaves_like 'it writes the raw data to a file and then uploads that file to S3 via TransferManager', 'public-read', 'private, max-age=0, no-cache', 'application/xml'
      end

      context 'with compress true' do
        let(:compress) { true }

        it_behaves_like 'it writes the raw data to a file and then uploads that file to S3 via TransferManager', 'public-read', 'private, max-age=0, no-cache', 'application/x-gzip'
      end

      context 'with acl and cache control configured' do
        let(:options) do
          { acl: 'private', cache_control: 'public, max-age=3600' }
        end

        it_behaves_like 'it writes the raw data to a file and then uploads that file to S3 via TransferManager', 'private', 'public, max-age=3600', 'application/xml'
      end
    end
  end

  describe '#initialize' do
    subject(:adapterOptions) { adapter.instance_variable_get(:@options) }

    it_behaves_like "deprecated option", :aws_endpoint, :endpoint
    it_behaves_like "deprecated option", :aws_access_key_id, :access_key_id
    it_behaves_like "deprecated option", :aws_secret_access_key, :secret_access_key
    it_behaves_like "deprecated option", :aws_region, :region
  end
end
