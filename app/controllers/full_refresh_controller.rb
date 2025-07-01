class FullRefreshController < ApplicationController
  http_basic_authenticate_with name: -> { Rails.application.credentials.good_job&.username },
                               password: -> { Rails.application.credentials.good_job&.password }

  def index
    @bases = []
    AirtableService::Bases.find_each do |base|
      @bases << base
    end
  end

  def create
    base_id = params[:base_id]
    
    if base_id.blank?
      redirect_to full_refresh_index_path, alert: "Please select a base"
      return
    end

    # Find the base to get its name for the flash message
    base = AirtableService::Bases.find_cached(base_id)
    base_name = base ? base['name'] : base_id
    
    # Queue the full refresh job
    FullRefreshJob.perform_later(base_id)
    
    redirect_to full_refresh_index_path, notice: "Full refresh initiated for base '#{base_name}'. Check the logs for progress."
  end
end
