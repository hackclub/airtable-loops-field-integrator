class SyncSourcesController < ApplicationController
  before_action :set_sync_source, only: [:show, :edit, :update, :destroy]

  def index
    # Fetch all Airtable bases
    begin
      @bases = AirtableService::Bases.find_each.to_a
      @sync_sources_by_base_id = SyncSource.where(source: 'airtable').index_by(&:source_id)
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

