require 'test_helper'

class Admin::ItemsControllerTest < ActionDispatch::IntegrationTest

  include ActiveJob::TestHelper # needed for assert_enqueued_with helper

  def before_all
    super
    @community = Community.new_locked_ldp_object(title: 'Desolate community',
                                                 owner: 1)
    @community.unlock_and_fetch_ldp_object(&:save!)
    @collection = Collection.new_locked_ldp_object(community_id: @community.id,
                                                   title: 'Desolate collection',
                                                   owner: 1)
    @collection.unlock_and_fetch_ldp_object(&:save!)

    @item = Item.new_locked_ldp_object(
      title: 'item for deletion',
      owner: 1,
      creators: ['Joe Blow'],
      created: '1972-08-08',
      languages: [CONTROLLED_VOCABULARIES[:language].english],
      license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international,
      visibility: JupiterCore::VISIBILITY_PUBLIC,
      item_type: CONTROLLED_VOCABULARIES[:item_type].article,
      publication_status: [CONTROLLED_VOCABULARIES[:publication_status].published],
      subject: ['Deletion'],
      doi: 'doi:10.5072/FK2JQ1005X'
    ).unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.add_to_path(@community.id, @collection.id)
      File.open(file_fixture('pdf-sample.pdf'), 'r') do |file|
        unlocked_item.add_files([file])
      end
      unlocked_item.save!
    end
  end

  def setup
    @admin = users(:admin)
    sign_in_as @admin
  end

  context '#destroy' do
    should 'destroy item and its derivatives' do
      assert_difference(['ItemDoiState.count', 'ActiveStorage::Blob.count'], 1) do
        @item.doi_state # ensure there is a doi to test deletion of
        @item.thumbnail_fileset(@item.file_sets.first) # ensure there is a thumbnail to test deletion of
      end

      assert_difference(['Item.count', 'ItemDoiState.count', 'ActiveStorage::Blob.count'], -1) do
        delete admin_item_url(@item)
      end

      assert_redirected_to root_path
      assert_equal I18n.t('admin.items.destroy.deleted'), flash[:notice]
    end
    should 'fail gracefully' do
      @item.unlock_and_fetch_ldp_object do |uo|
        def uo.destroy
          raise ActiveRecord::RecordNotDestroyed
        end
      end
      assert_no_difference(['Item.count', 'ItemDoiState.count', 'ActiveStorage::Blob.count']) do
        delete admin_item_url(@item)
      end

      assert_redirected_to root_path
      assert_equal I18n.t('admin.items.destroy.failed'), flash[:notice]
    end
  end

end
