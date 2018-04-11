class SearchController < ApplicationController

  QUERY_MAX = 500

  skip_after_action :verify_authorized

  def index
    # note that search_params depends on @models being an array, so we need to establish this first, before dealing w/
    # any params
    tab = params[:tab]
    tab ||= 'item'
    @models = case tab
              when 'item'
                [Item, Thesis]
              when 'collection'
                [Collection]
              when 'community'
                [Community]
              else
                return redirect_to search_path(tab: :item)
              end

    @active_tab = tab.to_sym

    # cut this off at a reasonable maximum to avoid DOSing Solr with truly huge queries (I managed to shove upwards
    # of 5000 characters in here locally)
    query = search_params[:search].truncate(QUERY_MAX) if search_params[:search].present?

    # Make sure selected facets/ranges and solr-only authors/subjects appear first in facet list
    @first_facet_categories = (search_params.fetch(:facets, {}).keys + search_params.fetch(:ranges, {}).keys).uniq
    @first_facet_categories ||= []
    if @active_tab == :item
      @first_facet_categories += [Item.solr_name_for(:all_contributors, role: :facet),
                                  Item.solr_name_for(:all_subjects, role: :facet)]
    end

    search_opts = { q: query, models: @models, as: current_user,
                    facets: search_params[:facets], ranges: search_params[:ranges] }

    @results = JupiterCore::Search.faceted_search(search_opts)

    # Toggle that we want to be able to sort by sort_year
    if @active_tab == :item
      @item_sort = true
      @results.sort(sort_column(columns: ['title', 'sort_year']), sort_direction).page search_params[:page]
    else
      @results.sort(sort_column, sort_direction).page search_params[:page]
    end
  end

  private

  def search_params
    r = {}
    f = {}
    @models.each do |model|
      model.ranges.each do |range|
        next unless params[:ranges].present? && params[:ranges][range].present?
        if validate_range(params[:ranges][range])
          r[range] = [:begin, :end]
        else
          params[:ranges].delete(range)
        end
      end
      model.facets.each do |facet|
        f[facet] = []
      end
    end
    params.permit(:tab, :page, :search, :direction, { facets: f }, ranges: r)
  end

  def validate_range(range)
    start = range[:begin]
    finish = range[:end]
    return true if start.match?(/\A\d{1,4}\z/) && finish.match?(/\A\d{1,4}\z/) && (start.to_i <= finish.to_i)
    flash[:alert] = "#{start} to #{finish} is not a valid range"
    false
  end

end
