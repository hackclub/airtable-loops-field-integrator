class SyncSourcesController < ApplicationController
  before_action :set_sync_source, only: [:show, :edit, :update, :destroy]

  def index
    # Fetch all Airtable bases
    begin
      @bases = AirtableService::Bases.find_each.to_a
      @sync_sources_by_base_id = SyncSource.where(source: 'airtable').index_by(&:source_id)
      
      # Sort bases to show active sync sources on top
      @bases.sort_by! do |base|
        sync_source = @sync_sources_by_base_id[base["id"]]
        if sync_source
          # Active sync sources (consecutive_failures == 0) come first
          sync_source.consecutive_failures == 0 ? 0 : 1
        else
          # Bases with no sync source come last
          2
        end
      end
    rescue => e
      @error = "Failed to fetch Airtable bases: #{e.message}"
      @bases = []
      @sync_sources_by_base_id = {}
    end
  end

  def show
  end

  def new
    @sync_source = AirtableSyncSource.new
    @base_id = params[:base_id]
    
    # Fetch available bases for dropdown
    begin
      @available_bases = AirtableService::Bases.find_each.to_a
    rescue => e
      @error = "Failed to fetch Airtable bases: #{e.message}"
      @available_bases = []
    end
  end

  def create
    @sync_source = AirtableSyncSource.new(sync_source_params)
    @sync_source.source = 'airtable'
    
    # Set display_name from Airtable base name if available
    if @sync_source.source_id.present?
      begin
        base = AirtableService::Bases.find_by_id(base_id: @sync_source.source_id)
        if base && base["name"]
          @sync_source.display_name = base["name"]
          @sync_source.display_name_updated_at = Time.current
        end
      rescue => e
        # Log error but don't fail creation if we can't fetch base name
        Rails.logger.warn("Failed to fetch base name for #{@sync_source.source_id}: #{e.message}")
      end
    end
    
    if @sync_source.save
      redirect_to sync_source_path(@sync_source), notice: 'Sync source was successfully created.'
    else
      begin
        @available_bases = AirtableService::Bases.find_each.to_a
      rescue => e
        @error = "Failed to fetch Airtable bases: #{e.message}"
        @available_bases = []
      end
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @sync_source.update(sync_source_params)
      redirect_to sync_source_path(@sync_source), notice: 'Sync source was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @sync_source.destroy
    redirect_to sync_sources_path, notice: 'Sync source was successfully deleted.'
  end

  private

  def set_sync_source
    @sync_source = SyncSource.find(params[:id])
  end

  def sync_source_params
    # Handle both sync_source and airtable_sync_source parameter names
    params.require(params[:sync_source] ? :sync_source : :airtable_sync_source).permit(:source_id, :poll_interval_seconds, :poll_jitter)
  end
end

